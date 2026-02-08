import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOHTTP2

final class HTTP2MITMClientStreamHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let processInfoProvider: ProcessInfoProvider
    private let trafficController: TrafficProfileController

    private let upstreamMultiplexer: HTTP2StreamMultiplexer

    private let authorityFallback: String
    private let scheme: String

    private var streamID: Int?
    private var upstreamStream: Channel?

    private var currentHead: HTTPRequestHead?
    private var currentBody: ByteBuffer?
    private var currentBodySize: Int = 0
    private var requestID: String?

    private enum InterceptorFailure: Error {
        case blocked
    }

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        processInfoProvider: ProcessInfoProvider,
        trafficController: TrafficProfileController,
        upstreamMultiplexer: HTTP2StreamMultiplexer,
        authorityFallback: String,
        scheme: String = "https"
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.processInfoProvider = processInfoProvider
        self.trafficController = trafficController
        self.upstreamMultiplexer = upstreamMultiplexer
        self.authorityFallback = authorityFallback
        self.scheme = scheme
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.getOption(HTTP2StreamChannelOptions.streamID).whenSuccess { id in
            self.streamID = Int(id)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let upstreamStream {
            upstreamStream.eventLoop.execute {
                upstreamStream.close(promise: nil)
            }
        }
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            currentHead = head
            currentBody = context.channel.allocator.buffer(capacity: 0)
            currentBodySize = 0
            requestID = Self.makeRequestID()

        case .body(var buffer):
            if currentBody == nil {
                currentBody = context.channel.allocator.buffer(capacity: buffer.readableBytes)
            }
            currentBodySize += buffer.readableBytes
            if var body = currentBody {
                body.writeBuffer(&buffer)
                currentBody = body
            }

        case .end:
            guard let head = currentHead else {
                reset()
                return
            }
            let reqID = requestID ?? Self.makeRequestID()
            let bodyBuffer = currentBody ?? context.channel.allocator.buffer(capacity: 0)
            let bodySize = currentBodySize
            reset()

            handleRequest(context: context, head: head, bodyBuffer: bodyBuffer, bodySize: bodySize, requestID: reqID)
        }
    }

    private func reset() {
        currentHead = nil
        currentBody = nil
        currentBodySize = 0
        requestID = nil
    }

    private func handleRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyBuffer: ByteBuffer,
        bodySize: Int,
        requestID: String
    ) {
        // Build a reasonable URL for capture purposes.
        let authority = head.headers.first(name: "Host") ?? authorityFallback
        let url: String
        if head.uri.hasPrefix("http://") || head.uri.hasPrefix("https://") {
            url = head.uri
        } else {
            let path = head.uri.hasPrefix("/") ? head.uri : "/" + head.uri
            url = "\(scheme)://\(authority)\(path)"
        }

        var request = ProxyRequest(
            id: requestID,
            httpVersion: .h2,
            streamID: streamID,
            method: head.method.rawValue,
            url: url,
            headers: head.headers.asFlatDictionary(),
            bodyPreview: bodyBuffer.getData(
                at: bodyBuffer.readerIndex,
                length: min(bodyBuffer.readableBytes, configuration.maxCapturedBodyBytes)
            ),
            bodyIsTruncated: bodySize > configuration.maxCapturedBodyBytes,
            rawBodySize: bodySize,
            client: context.channel.remoteAddress.map { ProxyClientInfo(ip: $0.ipAddress ?? "", port: $0.port) }
        )

        let processInfoFut: EventLoopFuture<ProxyProcessInfo?> = {
            guard let port = context.channel.remoteAddress?.port else {
                return context.eventLoop.makeSucceededFuture(nil)
            }
            return context.eventLoop.makeFutureWithTask {
                await self.processInfoProvider.processInfoForClientPort(port)
            }
        }()

        processInfoFut.flatMap { procInfo in
            if let procInfo {
                request.processInfo = procInfo
            }

            // Emit immediately so the UI can show the request even if interceptors later block it.
            self.eventBus.emit(.request(request))

            return self.applyOnRequestInterceptors(request, on: context.eventLoop).flatMap { updated in
                request = updated
                self.eventBus.emit(.request(request))

                return self.runExecuteInterceptors(request, on: context.eventLoop).flatMap { mocked in
                    if let mocked {
                        self.eventBus.emit(.response(mocked))
                        self.writeMockedResponse(context: context, mocked)
                        return context.eventLoop.makeSucceededFuture(())
                    }

                    return self.forwardToUpstream(context: context, originalHead: head, updatedRequest: request, bodyBuffer: bodyBuffer)
                }
            }
        }.flatMapError { error in
            if case InterceptorFailure.blocked = error {
                self.writeError(context: context, status: .forbidden, body: "Blocked")
                return context.eventLoop.makeSucceededFuture(())
            }

            self.eventBus.emit(.error(ProxyErrorEvent(requestID: requestID, message: String(describing: error))))
            self.writeError(context: context, status: .badGateway, body: "Proxy error")
            return context.eventLoop.makeSucceededFuture(())
        }.whenFailure { error in
            self.eventBus.emit(.log("[ProxyCore] MITM HTTP/2 stream error: \(error)\n"))
            context.close(promise: nil)
        }
    }

    private func forwardToUpstream(
        context: ChannelHandlerContext,
        originalHead: HTTPRequestHead,
        updatedRequest: ProxyRequest,
        bodyBuffer: ByteBuffer
    ) -> EventLoopFuture<Void> {
        if let upstreamStream {
            writeRequestParts(upstreamStream: upstreamStream, originalHead: originalHead, updatedRequest: updatedRequest, bodyBuffer: bodyBuffer)
            return context.eventLoop.makeSucceededFuture(())
        }

        let clientStream = context.channel
        let clientEventLoop = context.eventLoop

        // Create a corresponding upstream stream channel.
        return upstreamMultiplexer.createStreamChannel { channel in
            channel.eventLoop.makeCompletedFuture {
                // Use the non-deprecated codec that works with frame payloads.
                try channel.pipeline.syncOperations.addHandler(HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https))
                try channel.pipeline.syncOperations.addHandler(
                    HTTP2MITMUpstreamStreamHandler(
                        configuration: self.configuration,
                        eventBus: self.eventBus,
                        interceptors: self.interceptors,
                        trafficController: self.trafficController,
                        request: updatedRequest,
                        requestID: updatedRequest.id,
                        streamID: self.streamID,
                        clientStream: clientStream
                    )
                )
            }
        }.hop(to: clientEventLoop).map { upstreamStream in
            self.upstreamStream = upstreamStream
            self.writeRequestParts(
                upstreamStream: upstreamStream,
                originalHead: originalHead,
                updatedRequest: updatedRequest,
                bodyBuffer: bodyBuffer
            )
        }
    }

    private func writeRequestParts(
        upstreamStream: Channel,
        originalHead: HTTPRequestHead,
        updatedRequest: ProxyRequest,
        bodyBuffer: ByteBuffer
    ) {
        let (bodyToSend, _) = bodyBytesToSend(
            request: updatedRequest,
            fallback: bodyBuffer,
            fallbackSize: bodyBuffer.readableBytes,
            allocator: upstreamStream.allocator
        )

        let upstreamHead = Self.buildUpstreamRequestHead(
            original: originalHead,
            resolvedURL: updatedRequest.url,
            updatedHeaders: updatedRequest.headers,
            updatedMethod: updatedRequest.method,
            bodySize: bodyToSend?.readableBytes ?? 0,
            overrideContentLength: !updatedRequest.bodyIsTruncated && (bodyBuffer.readableBytes > 0 || (updatedRequest.bodyPreview?.isEmpty == false))
        )

        let delay = trafficController.delayFuture(
            direction: .uplink,
            byteCount: bodyToSend?.readableBytes ?? 0,
            on: upstreamStream.eventLoop
        )
        delay.whenComplete { _ in
            upstreamStream.eventLoop.execute {
                upstreamStream.write(NIOAny(HTTPClientRequestPart.head(upstreamHead)), promise: nil)
                if let bodyToSend, bodyToSend.readableBytes > 0 {
                    upstreamStream.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyToSend))), promise: nil)
                }
                upstreamStream.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
            }
        }
    }

    private func bodyBytesToSend(
        request: ProxyRequest,
        fallback: ByteBuffer,
        fallbackSize: Int,
        allocator: ByteBufferAllocator
    ) -> (ByteBuffer?, Int) {
        guard !request.bodyIsTruncated else {
            return (fallbackSize > 0 ? fallback : nil, fallbackSize)
        }
        let data = request.bodyPreview ?? Data()
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        return (data.isEmpty ? nil : buffer, data.count)
    }

    private func applyOnRequestInterceptors(_ request: ProxyRequest, on eventLoop: EventLoop) -> EventLoopFuture<ProxyRequest> {
        var fut: EventLoopFuture<ProxyRequest> = eventLoop.makeSucceededFuture(request)
        for interceptor in interceptors {
            fut = fut.flatMap { current in
                eventLoop.makeFutureWithTask {
                    await interceptor.onRequest(current)
                }.flatMapThrowing { updated in
                    guard let updated else { throw InterceptorFailure.blocked }
                    return updated
                }
            }
        }
        return fut
    }

    private func runExecuteInterceptors(_ request: ProxyRequest, on eventLoop: EventLoop) -> EventLoopFuture<ProxyResponse?> {
        func run(at index: Int) -> EventLoopFuture<ProxyResponse?> {
            guard index < interceptors.count else {
                return eventLoop.makeSucceededFuture(nil)
            }

            return eventLoop.makeFutureWithTask {
                await self.interceptors[index].execute(request)
            }.flatMap { response in
                if response != nil {
                    return eventLoop.makeSucceededFuture(response)
                }
                return run(at: index + 1)
            }
        }
        return run(at: 0)
    }

    private func writeMockedResponse(context: ChannelHandlerContext, _ response: ProxyResponse) {
        var head = HTTPResponseHead(
            version: HTTPVersion(major: 2, minor: 0),
            status: HTTPResponseStatus(statusCode: response.statusCode)
        )
        for (k, v) in response.headers {
            head.headers.replaceOrAdd(name: k, value: v)
        }

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        if let data = response.bodyPreview, !data.isEmpty {
            var buf = context.channel.allocator.buffer(capacity: data.count)
            buf.writeBytes(data)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func writeError(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var head = HTTPResponseHead(
            version: HTTPVersion(major: 2, minor: 0),
            status: status
        )
        head.headers.add(name: "content-type", value: "text/plain; charset=utf-8")
        let bytes = Array(body.utf8)
        head.headers.add(name: "content-length", value: "\(bytes.count)")

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private static func makeRequestID() -> String {
        let t = UInt64(Date().timeIntervalSince1970 * 1000)
        let r = UInt64.random(in: 0..<UInt64.max)
        return String((t ^ r), radix: 36)
    }

    private static func buildUpstreamRequestHead(
        original: HTTPRequestHead,
        resolvedURL: String,
        updatedHeaders: [String: String],
        updatedMethod: String,
        bodySize: Int,
        overrideContentLength: Bool
    ) -> HTTPRequestHead {
        var head = original
        head.method = HTTPMethod(rawValue: updatedMethod)

        head.headers = HTTPHeaders()
        for (k, v) in updatedHeaders {
            head.headers.add(name: k, value: v)
        }

        // For HTTP/2 codecs, origin-form is expected.
        if let url = URL(string: resolvedURL), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var path = comps.percentEncodedPath
            if path.isEmpty { path = "/" }
            if let q = comps.percentEncodedQuery, !q.isEmpty {
                path += "?" + q
            }
            head.uri = path
        }

        head.headers.remove(name: "Proxy-Connection")
        if overrideContentLength {
            head.headers.remove(name: "Transfer-Encoding")
            head.headers.replaceOrAdd(name: "Content-Length", value: "\(bodySize)")
        }
        return head
    }
}

final class HTTP2MITMUpstreamStreamHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let trafficController: TrafficProfileController

    private let request: ProxyRequest
    private let requestID: String
    private let streamID: Int?

    private let clientStream: Channel

    private var responseHead: HTTPResponseHead?
    private var bodyPreview = Data()
    private var bodySize = 0
    private var isSSE = false
    private var sseParser = SSEParser()

    // The upstream HTTP/2 stream channel becomes inactive as soon as both sides have ended the stream.
    // We must not close the client stream channel in response to that normal lifecycle event,
    // otherwise clients (curl) will observe an RST_STREAM(CANCEL) even though we have a full response buffered.
    private var didReceiveResponseHead = false
    private var didReceiveResponseEnd = false
    private var pendingBufferedResponseWrite = false

    private var bufferingResponse = false
    private var bufferedBody: Data?

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        trafficController: TrafficProfileController,
        request: ProxyRequest,
        requestID: String,
        streamID: Int?,
        clientStream: Channel
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.trafficController = trafficController
        self.request = request
        self.requestID = requestID
        self.streamID = streamID
        self.clientStream = clientStream
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Only reset the client stream if the upstream stream died before we received a complete response.
        if !didReceiveResponseEnd && !pendingBufferedResponseWrite {
            clientStream.eventLoop.execute {
                self.clientStream.close(promise: nil)
            }
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if !didReceiveResponseEnd && !pendingBufferedResponseWrite {
            clientStream.eventLoop.execute {
                self.clientStream.close(promise: nil)
            }
        }
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            didReceiveResponseHead = true
            responseHead = head
            bodyPreview.removeAll(keepingCapacity: true)
            bodySize = 0
            sseParser = SSEParser()
            if let ct = head.headers.first(name: "content-type")?.lowercased(), ct.contains("text/event-stream") {
                isSSE = true
            } else {
                isSSE = false
            }

            bufferingResponse = !isSSE
            if bufferingResponse {
                bufferedBody = Data()
            } else {
                bufferedBody = nil
                clientStream.eventLoop.execute {
                    var outHead = HTTPResponseHead(
                        version: HTTPVersion(major: 2, minor: 0),
                        status: head.status
                    )
                    outHead.headers = head.headers
                    if let profileID = self.trafficController.profileHeaderValue() {
                        outHead.headers.replaceOrAdd(name: "x-frtraffic-profile", value: profileID)
                    }
                    self.clientStream.write(NIOAny(HTTPServerResponsePart.head(outHead)), promise: nil)
                }
            }

        case .body(let buffer):
            var buf = buffer
            bodySize += buf.readableBytes
            if bodyPreview.count < configuration.maxCapturedBodyBytes {
                let toCopy = min(configuration.maxCapturedBodyBytes - bodyPreview.count, buf.readableBytes)
                if let bytes = buf.readBytes(length: toCopy) {
                    bodyPreview.append(contentsOf: bytes)
                }
            }

            if bufferingResponse {
                var copy = buffer
                if let bytes = copy.readBytes(length: copy.readableBytes) {
                    bufferedBody?.append(contentsOf: bytes)
                }

                if let buffered = bufferedBody, buffered.count > configuration.maxCapturedBodyBytes {
                    bufferingResponse = false
                    bufferedBody = nil

                    if let head = responseHead {
                        clientStream.eventLoop.execute {
                            var outHead = HTTPResponseHead(
                                version: HTTPVersion(major: 2, minor: 0),
                                status: head.status
                            )
                            outHead.headers = head.headers
                            self.clientStream.write(NIOAny(HTTPServerResponsePart.head(outHead)), promise: nil)

                            var out = self.clientStream.allocator.buffer(capacity: buffered.count)
                            out.writeBytes(buffered)
                            self.clientStream.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(out))), promise: nil)
                        }
                    }
                }
            } else {
                clientStream.eventLoop.execute {
                    // Flush each chunk to support streaming responses (SSE, etc).
                    self.clientStream.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                }

                if isSSE {
                    for e in sseParser.append(buffer) {
                        eventBus.emit(.sseEvent(ProxySSEEvent(
                            requestID: requestID,
                            event: e.event,
                            id: e.id,
                            data: e.data
                        )))
                    }
                }
            }

        case .end:
            didReceiveResponseEnd = true
            if bufferingResponse, let head = responseHead {
                bufferingResponse = false
                let body = bufferedBody ?? Data()
                bufferedBody = nil
                pendingBufferedResponseWrite = true
                context.eventLoop.makeFutureWithTask {
                    await self.interceptAndWriteBufferedResponse(head: head, body: body)
                }.whenComplete { _ in
                    self.pendingBufferedResponseWrite = false
                }
            } else {
                clientStream.eventLoop.execute {
                    self.clientStream.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                }

                if let head = responseHead {
                    Task {
                        await self.emitAndInterceptResponse(head: head)
                    }
                }
            }

            responseHead = nil
        }
    }

    private func interceptAndWriteBufferedResponse(head: HTTPResponseHead, body: Data) async {
        var proxyResponse = ProxyResponse(
            requestID: requestID,
            httpVersion: .h2,
            streamID: streamID,
            statusCode: Int(head.status.code),
            headers: head.headers.asFlatDictionary(),
            bodyPreview: body,
            bodyIsTruncated: false,
            rawBodySize: body.count
        )

        for interceptor in interceptors {
            if let updated = await interceptor.onResponse(request: request, response: proxyResponse) {
                proxyResponse = updated
            } else {
                // Blocked response: send a generic error to avoid hanging the stream.
                clientStream.eventLoop.execute {
                    var outHead = HTTPResponseHead(
                        version: HTTPVersion(major: 2, minor: 0),
                        status: .forbidden
                    )
                    let msg = "Blocked"
                    outHead.headers.add(name: "content-type", value: "text/plain; charset=utf-8")
                    outHead.headers.replaceOrAdd(name: "content-length", value: "\(msg.utf8.count)")

                    self.clientStream.write(NIOAny(HTTPServerResponsePart.head(outHead)), promise: nil)
                    var buf = self.clientStream.allocator.buffer(capacity: msg.utf8.count)
                    buf.writeString(msg)
                    self.clientStream.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
                    self.clientStream.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                }
                return
            }
        }

        if let profileID = trafficController.profileHeaderValue() {
            proxyResponse.headers["x-frtraffic-profile"] = profileID
        }

        if trafficController.shouldInjectPacketLoss() {
            let message = "Simulated packet loss (traffic profile)"
            let data = Data(message.utf8)
            proxyResponse.statusCode = 598
            proxyResponse.bodyPreview = data
            proxyResponse.bodyIsTruncated = false
            proxyResponse.rawBodySize = data.count
            ensureContentTypePlainText(&proxyResponse.headers)
        }

        let outBody = proxyResponse.bodyPreview ?? Data()
        let outHeaders = proxyResponse.headers
        let outStatus = proxyResponse.statusCode

        let delay = trafficController.delayFuture(direction: .downlink, byteCount: outBody.count, on: clientStream.eventLoop)
        delay.whenComplete { _ in
            self.clientStream.eventLoop.execute {
                var outHead = HTTPResponseHead(
                    version: HTTPVersion(major: 2, minor: 0),
                    status: HTTPResponseStatus(statusCode: outStatus)
                )
                outHead.headers = HTTPHeaders()
                for (k, v) in outHeaders {
                    outHead.headers.add(name: k, value: v)
                }
                outHead.headers.remove(name: "transfer-encoding")
                outHead.headers.replaceOrAdd(name: "content-length", value: "\(outBody.count)")

                self.clientStream.write(NIOAny(HTTPServerResponsePart.head(outHead)), promise: nil)
                if !outBody.isEmpty {
                    var buf = self.clientStream.allocator.buffer(capacity: outBody.count)
                    buf.writeBytes(outBody)
                    self.clientStream.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
                }
                self.clientStream.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            }

            self.eventBus.emit(.response(proxyResponse))
        }
    }

    private func ensureContentTypePlainText(_ headers: inout [String: String]) {
        for (k, _) in headers where k.lowercased() == "content-type" {
            return
        }
        headers["content-type"] = "text/plain; charset=utf-8"
    }

    private func emitAndInterceptResponse(head: HTTPResponseHead) async {
        var proxyResponse = ProxyResponse(
            requestID: requestID,
            httpVersion: .h2,
            streamID: streamID,
            statusCode: Int(head.status.code),
            headers: head.headers.asFlatDictionary(),
            bodyPreview: bodyPreview,
            bodyIsTruncated: bodySize > configuration.maxCapturedBodyBytes,
            rawBodySize: bodySize
        )

        for interceptor in interceptors {
            if let updated = await interceptor.onResponse(request: request, response: proxyResponse) {
                proxyResponse = updated
            } else {
                return
            }
        }

        eventBus.emit(.response(proxyResponse))
    }
}
