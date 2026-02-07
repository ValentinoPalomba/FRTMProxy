import Foundation
import NIO
import NIOHTTP1

final class HTTP1UpstreamHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let request: ProxyRequest
    private let clientChannel: Channel

    private var responseHead: HTTPResponseHead?
    private var bodyPreview = Data()
    private var bodySize = 0
    private var isWebSocketUpgrade = false

    private var isSSE = false
    private var sseParser = SSEParser()

    // When possible, buffer the full response to allow onResponse interceptors to rewrite/block before bytes
    // are written to the client. We fall back to streaming once the body exceeds `maxCapturedBodyBytes` or
    // when the protocol requires streaming (SSE/WebSocket upgrade).
    private var bufferingResponse = false
    private var bufferedBody: Data?

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        request: ProxyRequest,
        clientChannel: Channel
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.request = request
        self.clientChannel = clientChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
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
                    self.clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
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

            if isSSE {
                for e in sseParser.append(buffer) {
                    eventBus.emit(.sseEvent(ProxySSEEvent(
                        requestID: request.id,
                        event: e.event,
                        id: e.id,
                        data: e.data
                    )))
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
            }

        case .end:
            if bufferingResponse, let head = responseHead {
                bufferingResponse = false
                let body = bufferedBody ?? Data()
                bufferedBody = nil

                Task {
                    await self.interceptAndWriteBufferedResponse(head: head, body: body)
                }
            } else {
                clientChannel.eventLoop.execute {
                    self.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                }

                if let head = responseHead {
                    Task {
                        await self.emitAndInterceptResponse(head: head)
                    }
                }
            }

            if isWebSocketUpgrade {
                WebSocketProxy.switchToWebSocket(
                    requestID: request.id,
                    configuration: configuration,
                    eventBus: eventBus,
                    clientChannel: clientChannel,
                    upstreamChannel: context.channel
                ).whenFailure { error in
                    self.eventBus.emit(.log("[ProxyCore] WebSocket switch failed: \(String(reflecting: error))\n"))
                    context.close(promise: nil)
                }
            } else {
                context.close(promise: nil)
            }
        }
    }

    private func interceptAndWriteBufferedResponse(head: HTTPResponseHead, body: Data) async {
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

        // Write the (possibly modified) response to the client.
        let outBody = proxyResponse.bodyPreview ?? Data()
        let outHeaders = proxyResponse.headers
        let outStatus = proxyResponse.statusCode

        clientChannel.eventLoop.execute {
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

        eventBus.emit(.response(proxyResponse))
    }

    private func emitAndInterceptResponse(head: HTTPResponseHead) async {
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
                // Blocked response: no-op (client already received it).
                return
            }
        }

        eventBus.emit(.response(proxyResponse))
    }
}
