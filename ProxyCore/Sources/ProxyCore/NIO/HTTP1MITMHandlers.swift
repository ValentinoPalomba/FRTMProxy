import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOFoundationCompat

final class HTTP1MITMSession: @unchecked Sendable {
    private let lock = NIOLock()
    private var pending: [ProxyRequest] = []
    private var index: Int = 0

    func enqueue(_ request: ProxyRequest) {
        lock.withLock {
            pending.append(request)
        }
    }

    func dequeue() -> ProxyRequest? {
        lock.withLock {
            guard index < pending.count else { return nil }
            let req = pending[index]
            index += 1

            // Periodically compact the buffer to avoid unbounded growth.
            if index > 64 {
                pending.removeFirst(index)
                index = 0
            }
            return req
        }
    }
}

final class HTTP1MITMFrontendHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let processInfoProvider: ProcessInfoProvider
    private let trafficController: TrafficProfileController

    private let upstreamChannel: Channel
    private let session: HTTP1MITMSession

    private let targetHost: String
    private let targetPort: Int

    private var currentHead: HTTPRequestHead?
    private var currentBody: ByteBuffer?
    private var currentBodySize: Int = 0
    private var currentRequestID: String?

    private enum InterceptorFailure: Error {
        case blocked
    }

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        processInfoProvider: ProcessInfoProvider,
        trafficController: TrafficProfileController,
        upstreamChannel: Channel,
        session: HTTP1MITMSession,
        targetHost: String,
        targetPort: Int
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.processInfoProvider = processInfoProvider
        self.trafficController = trafficController
        self.upstreamChannel = upstreamChannel
        self.session = session
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        reset()
    }

    func channelInactive(context: ChannelHandlerContext) {
        upstreamChannel.eventLoop.execute {
            self.upstreamChannel.close(promise: nil)
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
            currentRequestID = Self.makeRequestID()

        case .body(var buffer):
            if currentBody == nil {
                currentBody = context.channel.allocator.buffer(capacity: buffer.readableBytes)
            }
            let readable = buffer.readableBytes
            currentBodySize += readable
            if var body = currentBody {
                body.writeBuffer(&buffer)
                currentBody = body
            }

        case .end:
            guard let head = currentHead else {
                reset()
                return
            }
            let requestID = currentRequestID ?? Self.makeRequestID()
            let bodyBuffer = currentBody ?? context.channel.allocator.buffer(capacity: 0)
            let bodySize = currentBodySize
            reset()

            handleRequest(context: context, head: head, bodyBuffer: bodyBuffer, bodySize: bodySize, requestID: requestID)
        }
    }

    private func reset() {
        currentHead = nil
        currentBody = nil
        currentBodySize = 0
        currentRequestID = nil
    }

    private func handleRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyBuffer: ByteBuffer,
        bodySize: Int,
        requestID: String
    ) {
        // We don't expect CONNECT inside a tunneled connection.
        if head.method == .CONNECT {
            writeError(context: context, status: .badRequest, body: "CONNECT not allowed in tunnel")
            return
        }

        let authority = Self.bestEffortAuthority(from: head, fallbackHost: targetHost, fallbackPort: targetPort)
        let url = Self.bestEffortURL(from: head, authority: authority, defaultScheme: "https")

        var request = ProxyRequest(
            id: requestID,
            httpVersion: .http1_1,
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

                return self.runExecuteInterceptors(request, on: context.eventLoop).map { mocked in
                    if let mocked {
                        self.eventBus.emit(.response(mocked))
                        self.writeProxyResponse(context: context, response: mocked)
                        return
                    }

                    self.session.enqueue(request)
                    self.forwardToUpstream(head: head, updatedRequest: request, bodyBuffer: bodyBuffer, bodySize: bodySize)
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
            // Best-effort: close the connection if something unexpected happens.
            self.eventBus.emit(.log("[ProxyCore] MITM HTTP/1 handler error: \(error)\n"))
            context.close(promise: nil)
        }
    }

    private func forwardToUpstream(head: HTTPRequestHead, updatedRequest: ProxyRequest, bodyBuffer: ByteBuffer, bodySize: Int) {
        let (bodyToSend, _) = bodyBytesToSend(
            request: updatedRequest,
            fallback: bodyBuffer,
            fallbackSize: bodySize,
            allocator: upstreamChannel.allocator
        )

        let upstreamHead = Self.buildUpstreamRequestHead(
            original: head,
            resolvedURL: updatedRequest.url,
            updatedHeaders: updatedRequest.headers,
            updatedMethod: updatedRequest.method,
            bodySize: bodyToSend?.readableBytes ?? 0,
            overrideContentLength: !updatedRequest.bodyIsTruncated && (bodySize > 0 || (updatedRequest.bodyPreview?.isEmpty == false))
        )

        let delay = trafficController.delayFuture(
            direction: .uplink,
            byteCount: bodyToSend?.readableBytes ?? 0,
            on: upstreamChannel.eventLoop
        )
        delay.whenComplete { _ in
            self.upstreamChannel.eventLoop.execute {
                self.upstreamChannel.write(NIOAny(HTTPClientRequestPart.head(upstreamHead)), promise: nil)
                if let bodyToSend, bodyToSend.readableBytes > 0 {
                    self.upstreamChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyToSend))), promise: nil)
                }
                self.upstreamChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
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

    private func writeProxyResponse(context: ChannelHandlerContext, response: ProxyResponse) {
        var head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: response.statusCode))
        for (k, v) in response.headers {
            head.headers.replaceOrAdd(name: k, value: v)
        }

        let bodyData = response.bodyPreview ?? Data()
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(bodyData.count)")
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if !bodyData.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: bodyData.count)
            buffer.writeBytes(bodyData)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func writeError(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        head.headers.add(name: "Connection", value: "close")
        head.headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private static func makeRequestID() -> String {
        let t = UInt64(Date().timeIntervalSince1970 * 1000)
        let r = UInt64.random(in: 0..<UInt64.max)
        return String((t ^ r), radix: 36)
    }

    private static func bestEffortAuthority(from head: HTTPRequestHead, fallbackHost: String, fallbackPort: Int) -> String {
        if let host = head.headers.first(name: "Host"), !host.isEmpty {
            return host
        }
        return fallbackPort == 443 ? fallbackHost : "\(fallbackHost):\(fallbackPort)"
    }

    private static func bestEffortURL(from head: HTTPRequestHead, authority: String, defaultScheme: String) -> String {
        if head.uri.hasPrefix("http://") || head.uri.hasPrefix("https://") {
            return head.uri
        }
        let path = head.uri.hasPrefix("/") ? head.uri : "/" + head.uri
        return "\(defaultScheme)://\(authority)\(path)"
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

        // Normalize absolute-form to origin-form if needed.
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

final class HTTP1MITMUpstreamHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let trafficController: TrafficProfileController

    private let clientChannel: Channel
    private let session: HTTP1MITMSession

    private var currentRequest: ProxyRequest?

    private var responseHead: HTTPResponseHead?
    private var bodyPreview = Data()
    private var bodySize = 0
    private var isWebSocketUpgrade = false

    private var isSSE = false
    private var sseParser = SSEParser()

    private var bufferingResponse = false
    private var bufferedBody: Data?

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        trafficController: TrafficProfileController,
        clientChannel: Channel,
        session: HTTP1MITMSession
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.trafficController = trafficController
        self.clientChannel = clientChannel
        self.session = session
    }

    func channelInactive(context: ChannelHandlerContext) {
        clientChannel.eventLoop.execute {
            self.clientChannel.close(promise: nil)
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        clientChannel.eventLoop.execute {
            self.clientChannel.close(promise: nil)
        }
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            currentRequest = session.dequeue() ?? currentRequest
            responseHead = head
            bodyPreview.removeAll(keepingCapacity: true)
            bodySize = 0
            isWebSocketUpgrade = WebSocketProxy.isWebSocketUpgradeResponse(head)

            sseParser = SSEParser()
            if let ct = head.headers.first(name: "Content-Type")?.lowercased(), ct.contains("text/event-stream") {
                isSSE = true
            } else {
                isSSE = false
            }

            bufferingResponse = !isWebSocketUpgrade && !isSSE
            if bufferingResponse {
                bufferedBody = Data()
            } else {
                bufferedBody = nil
                clientChannel.eventLoop.execute {
                    var serverHead = HTTPResponseHead(version: head.version, status: head.status)
                    serverHead.headers = head.headers
                    if let profileID = self.trafficController.profileHeaderValue() {
                        serverHead.headers.replaceOrAdd(name: "X-FRTraffic-Profile", value: profileID)
                    }
                    self.clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
                }
            }

            if currentRequest == nil {
                eventBus.emit(.log("[ProxyCore] MITM upstream response without matching request\n"))
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

                // If the response grows too large, fall back to streaming (cannot rewrite on-wire).
                if let buffered = bufferedBody, buffered.count > configuration.maxCapturedBodyBytes {
                    bufferingResponse = false
                    bufferedBody = nil

                    if let head = responseHead {
                        clientChannel.eventLoop.execute {
                            var serverHead = HTTPResponseHead(version: head.version, status: head.status)
                            serverHead.headers = head.headers
                            self.clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)

                            var out = self.clientChannel.allocator.buffer(capacity: buffered.count)
                            out.writeBytes(buffered)
                            self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(out))), promise: nil)
                        }
                    }
                }
            } else {
                clientChannel.eventLoop.execute {
                    // Flush each chunk to support streaming responses (SSE, chunked, etc).
                    self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                }

                if isSSE, let requestID = currentRequest?.id {
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
            if bufferingResponse, let head = responseHead, let req = currentRequest {
                bufferingResponse = false
                let body = bufferedBody ?? Data()
                bufferedBody = nil

                Task {
                    await self.interceptAndWriteBufferedResponse(request: req, head: head, body: body)
                }
            } else {
                clientChannel.eventLoop.execute {
                    self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                }

                if let head = responseHead, let req = currentRequest {
                    Task {
                        await self.emitAndInterceptResponse(request: req, head: head)
                    }
                }
            }

            if isWebSocketUpgrade, let requestID = currentRequest?.id {
                WebSocketProxy.switchToWebSocket(
                    requestID: requestID,
                    configuration: configuration,
                    eventBus: eventBus,
                    clientChannel: clientChannel,
                    upstreamChannel: context.channel
                ).whenFailure { error in
                    self.eventBus.emit(.log("[ProxyCore] WebSocket switch failed: \(String(reflecting: error))\n"))
                    context.close(promise: nil)
                }
            }

            // Reset for next response.
            responseHead = nil
            currentRequest = nil
        }
    }

    private func interceptAndWriteBufferedResponse(request: ProxyRequest, head: HTTPResponseHead, body: Data) async {
        var proxyResponse = ProxyResponse(
            requestID: request.id,
            httpVersion: .http1_1,
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
                // Blocked response: send a generic error to avoid hanging the client.
                clientChannel.eventLoop.execute {
                    var errHead = HTTPResponseHead(version: head.version, status: .forbidden)
                    let msg = "Blocked"
                    errHead.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                    errHead.headers.replaceOrAdd(name: "Content-Length", value: "\(msg.utf8.count)")
                    self.clientChannel.write(NIOAny(HTTPServerResponsePart.head(errHead)), promise: nil)
                    var buf = self.clientChannel.allocator.buffer(capacity: msg.utf8.count)
                    buf.writeString(msg)
                    self.clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
                    self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                }
                return
            }
        }

        if let profileID = trafficController.profileHeaderValue() {
            proxyResponse.headers["X-FRTraffic-Profile"] = profileID
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

        let delay = trafficController.delayFuture(direction: .downlink, byteCount: outBody.count, on: clientChannel.eventLoop)
        delay.whenComplete { _ in
            self.clientChannel.eventLoop.execute {
                var serverHead = HTTPResponseHead(version: head.version, status: HTTPResponseStatus(statusCode: outStatus))
                serverHead.headers = HTTPHeaders()
                for (k, v) in outHeaders {
                    serverHead.headers.add(name: k, value: v)
                }
                serverHead.headers.remove(name: "Transfer-Encoding")
                serverHead.headers.replaceOrAdd(name: "Content-Length", value: "\(outBody.count)")

                self.clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
                if !outBody.isEmpty {
                    var buf = self.clientChannel.allocator.buffer(capacity: outBody.count)
                    buf.writeBytes(outBody)
                    self.clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
                }
                self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            }

            self.eventBus.emit(.response(proxyResponse))
        }
    }

    private func ensureContentTypePlainText(_ headers: inout [String: String]) {
        for (k, _) in headers where k.lowercased() == "content-type" {
            return
        }
        headers["Content-Type"] = "text/plain; charset=utf-8"
    }

    private func emitAndInterceptResponse(request: ProxyRequest, head: HTTPResponseHead) async {
        var proxyResponse = ProxyResponse(
            requestID: request.id,
            httpVersion: .http1_1,
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
