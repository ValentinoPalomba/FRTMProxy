import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat

final class HTTP1FrontendHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let certificateAuthority: CertificateAuthority
    private let processInfoProvider: ProcessInfoProvider
    private let group: EventLoopGroup

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
        certificateAuthority: CertificateAuthority,
        processInfoProvider: ProcessInfoProvider,
        group: EventLoopGroup
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.certificateAuthority = certificateAuthority
        self.processInfoProvider = processInfoProvider
        self.group = group
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

            if head.method == .CONNECT {
                handleConnect(context: context, head: head, requestID: requestID)
                reset()
                return
            }

            self.handleHTTP1Request(
                context: context,
                head: head,
                bodyBuffer: bodyBuffer,
                bodySize: bodySize,
                requestID: requestID
            ).whenFailure { error in
                self.eventBus.emit(.log("[ProxyCore] HTTP/1 request failed: \(error)\n"))
                context.close(promise: nil)
            }

            reset()
        }
    }

    private func reset() {
        currentHead = nil
        currentBody = nil
        currentBodySize = 0
        currentRequestID = nil
    }

    private func handleConnect(context: ChannelHandlerContext, head: HTTPRequestHead, requestID: String) {
        let uri = head.uri
        let hostPort = HostAndPort.parseConnectAuthority(uri)
        guard let hostPort else {
            writeError(context: context, status: .badRequest, body: "Invalid CONNECT authority")
            return
        }

        // Respond 200 Connection established
        var responseHead = HTTPResponseHead(
            version: head.version,
            status: HTTPResponseStatus(statusCode: 200, reasonPhrase: "Connection established")
        )
        responseHead.headers.add(name: "Connection", value: "keep-alive")
        // A CONNECT response must not use chunked encoding; some clients treat any bytes after the
        // headers as tunneled data. Setting Content-Length avoids NIO's automatic chunked encoding.
        responseHead.headers.add(name: "Content-Length", value: "0")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            self.switchToTunnel(
                context: context,
                targetHost: hostPort.host,
                targetPort: hostPort.port,
                requestID: requestID
            )
        }
    }

    private func switchToTunnel(context: ChannelHandlerContext, targetHost: String, targetPort: Int, requestID: String) {
        let tunnel = ConnectTunnelHandler(
            configuration: configuration,
            eventBus: eventBus,
            interceptors: interceptors,
            certificateAuthority: certificateAuthority,
            processInfoProvider: processInfoProvider,
            group: group,
            targetHost: targetHost,
            targetPort: targetPort,
            connectRequestID: requestID
        )

        // Remove HTTP decoding/encoding and replace with raw ByteBuffer tunneling.
        let pipeline = context.channel.pipeline
        pipeline.removeHTTPServerHandlersIfPresent().flatMap {
            pipeline.addHandler(tunnel)
        }.flatMap {
            pipeline.removeHandler(self)
        }.whenFailure { error in
            self.eventBus.emit(.log("[ProxyCore] Failed to switch to tunnel: \(error)\n"))
            context.close(promise: nil)
        }
    }

    private func handleHTTP1Request(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyBuffer: ByteBuffer,
        bodySize: Int,
        requestID: String
    ) -> EventLoopFuture<Void> {
        let eventLoop = context.eventLoop

        // Local endpoints: /ssl and /config.
        return handleLocalEndpointsIfNeeded(context: context, head: head).flatMap { handled in
            if handled {
                return eventLoop.makeSucceededFuture(())
            }

            // Determine destination endpoint.
            guard let rawEndpoint = HostAndPort.resolveForHTTPProxyRequest(head: head, defaultPort: 80) else {
                self.writeError(context: context, status: .badRequest, body: "Missing Host")
                return eventLoop.makeSucceededFuture(())
            }

            let requestURL = rawEndpoint.requestURL(for: head.uri, defaultScheme: "http")

            var initialRequest = ProxyRequest(
                id: requestID,
                httpVersion: .http1_1,
                method: head.method.rawValue,
                url: requestURL,
                headers: head.headers.asFlatDictionary(),
                bodyPreview: bodyBuffer.getData(
                    at: bodyBuffer.readerIndex,
                    length: min(bodyBuffer.readableBytes, self.configuration.maxCapturedBodyBytes)
                ),
                bodyIsTruncated: bodySize > self.configuration.maxCapturedBodyBytes,
                rawBodySize: bodySize,
                client: context.channel.remoteAddress.map { ProxyClientInfo(ip: $0.ipAddress ?? "", port: $0.port) }
            )

            let processInfoFut: EventLoopFuture<ProxyProcessInfo?> = {
                guard let port = context.channel.remoteAddress?.port else {
                    return eventLoop.makeSucceededFuture(nil)
                }
                return eventLoop.makeFutureWithTask {
                    await self.processInfoProvider.processInfoForClientPort(port)
                }
            }()

            return processInfoFut.flatMap { procInfo in
                if let procInfo {
                    initialRequest.processInfo = procInfo
                }

                // Emit immediately so the UI can show the request even if interceptors later block it.
                self.eventBus.emit(.request(initialRequest))

                // HostFilter parity with ProxyPin: if the host is filtered, bypass interceptors and relay.
                if self.configuration.hostFilter.shouldFilter(host: rawEndpoint.host) {
                    self.eventBus.emit(.log("[ProxyCore] HostFilter bypass \(rawEndpoint.host)\n"))

                    let requestToSend = initialRequest
                    return self.connectUpstreamHTTP1(
                        to: rawEndpoint.host,
                        port: rawEndpoint.port,
                        clientChannel: context.channel,
                        request: requestToSend
                    ).hop(to: eventLoop).map { upstream in
                        // Best-effort: allow onRequest interceptors to change the body when it's fully captured.
                        let (bodyToSend, _) = self.bodyBytesToSend(
                            request: requestToSend,
                            fallback: bodyBuffer,
                            fallbackSize: bodySize,
                            allocator: context.channel.allocator
                        )

                        let headToSend = self.buildUpstreamRequestHead(
                            original: head,
                            resolvedURL: requestToSend.url,
                            endpoint: rawEndpoint,
                            updatedHeaders: requestToSend.headers,
                            updatedMethod: requestToSend.method,
                            useAbsoluteForm: self.configuration.externalProxy != nil,
                            proxyAuthorization: self.configuration.externalProxy?.basicAuthHeaderValue(),
                            bodySize: bodyToSend?.readableBytes ?? 0,
                            overrideContentLength: !requestToSend.bodyIsTruncated && (bodySize > 0 || (requestToSend.bodyPreview?.isEmpty == false))
                        )

                        upstream.eventLoop.execute {
                            upstream.write(NIOAny(HTTPClientRequestPart.head(headToSend)), promise: nil)
                            if let bodyToSend, bodyToSend.readableBytes > 0 {
                                upstream.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyToSend))), promise: nil)
                            }
                            upstream.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
                        }
                    }.flatMapError { error in
                        self.eventBus.emit(.error(ProxyErrorEvent(requestID: requestID, message: String(describing: error))))
                        self.writeError(context: context, status: .badGateway, body: "Upstream error")
                        return eventLoop.makeSucceededFuture(())
                    }
                }

                // Interceptors (onRequest -> execute -> preConnect) so URL edits can affect routing.
                return self.applyOnRequestInterceptors(initialRequest, on: eventLoop).flatMap { updatedRequest in
                    self.eventBus.emit(.request(updatedRequest))

                    return self.runExecuteInterceptors(updatedRequest, on: eventLoop).flatMap { mocked in
                        if let mocked {
                            self.eventBus.emit(.response(mocked))
                            self.writeProxyResponse(context: context, response: mocked)
                            return eventLoop.makeSucceededFuture(())
                        }

                        guard let resolvedEndpoint = HostAndPort.resolveForURLString(updatedRequest.url, defaultPort: 80) else {
                            self.writeError(context: context, status: .badRequest, body: "Invalid URL")
                            return eventLoop.makeSucceededFuture(())
                        }

                        let endpoint = ProxyEndpoint(host: resolvedEndpoint.host, port: resolvedEndpoint.port, isTLS: false)
                        return self.applyPreConnectInterceptors(endpoint, on: eventLoop).flatMap { updatedEndpoint in
                            let requestToSend = updatedRequest

                            // Forward upstream.
                            return self.connectUpstreamHTTP1(
                                to: updatedEndpoint.host,
                                port: updatedEndpoint.port,
                                clientChannel: context.channel,
                                request: requestToSend
                            ).hop(to: eventLoop).map { upstream in
                                // Best-effort: allow onRequest interceptors to change the body when it's fully captured.
                                let (bodyToSend, _) = self.bodyBytesToSend(
                                    request: requestToSend,
                                    fallback: bodyBuffer,
                                    fallbackSize: bodySize,
                                    allocator: context.channel.allocator
                                )

                                let headToSend = self.buildUpstreamRequestHead(
                                    original: head,
                                    resolvedURL: requestToSend.url,
                                    endpoint: resolvedEndpoint,
                                    updatedHeaders: requestToSend.headers,
                                    updatedMethod: requestToSend.method,
                                    useAbsoluteForm: self.configuration.externalProxy != nil,
                                    proxyAuthorization: self.configuration.externalProxy?.basicAuthHeaderValue(),
                                    bodySize: bodyToSend?.readableBytes ?? 0,
                                    overrideContentLength: !requestToSend.bodyIsTruncated && (bodySize > 0 || (requestToSend.bodyPreview?.isEmpty == false))
                                )

                                upstream.eventLoop.execute {
                                    upstream.write(NIOAny(HTTPClientRequestPart.head(headToSend)), promise: nil)
                                    if let bodyToSend, bodyToSend.readableBytes > 0 {
                                        upstream.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyToSend))), promise: nil)
                                    }
                                    upstream.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
                                }
                            }.flatMapError { error in
                                self.eventBus.emit(.error(ProxyErrorEvent(requestID: requestID, message: String(describing: error))))
                                self.writeError(context: context, status: .badGateway, body: "Upstream error")
                                return eventLoop.makeSucceededFuture(())
                            }
                        }
                    }
                }.flatMapError { error in
                    if case InterceptorFailure.blocked = error {
                        self.writeError(context: context, status: .forbidden, body: "Blocked")
                        return eventLoop.makeSucceededFuture(())
                    }
                    return eventLoop.makeFailedFuture(error)
                }
            }
        }
    }

    private func connectUpstreamHTTP1(to host: String, port: Int, clientChannel: Channel, request: ProxyRequest) -> EventLoopFuture<Channel> {
        let connectHost = configuration.externalProxy?.host ?? host
        let connectPort = configuration.externalProxy?.port ?? port
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(HTTP1UpstreamHandler(
                        configuration: self.configuration,
                        eventBus: self.eventBus,
                        interceptors: self.interceptors,
                        request: request,
                        clientChannel: clientChannel
                    ))
                }
            }

        return bootstrap.connect(host: connectHost, port: connectPort)
    }

    private func buildUpstreamRequestHead(
        original: HTTPRequestHead,
        resolvedURL: String,
        endpoint: HostAndPort,
        updatedHeaders: [String: String],
        updatedMethod: String,
        useAbsoluteForm: Bool,
        proxyAuthorization: String?,
        bodySize: Int,
        overrideContentLength: Bool
    ) -> HTTPRequestHead {
        var head = original

        head.method = HTTPMethod(rawValue: updatedMethod)

        // Apply header updates from interceptors.
        head.headers = HTTPHeaders()
        for (k, v) in updatedHeaders {
            head.headers.add(name: k, value: v)
        }

        if useAbsoluteForm {
            // Forward to another proxy: keep absolute-form.
            head.uri = resolvedURL
        } else {
            // Direct upstream: convert absolute-form to origin-form.
            if let url = URL(string: resolvedURL), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var path = comps.percentEncodedPath
                if path.isEmpty { path = "/" }
                if let q = comps.percentEncodedQuery, !q.isEmpty {
                    path += "?" + q
                }
                head.uri = path
            }
        }

        if head.headers.first(name: "Host") == nil {
            head.headers.add(name: "Host", value: endpoint.hostHeaderValue)
        }

        // Prevent leaking inbound proxy credentials/upstream proxy headers.
        head.headers.remove(name: "Proxy-Connection")
        head.headers.remove(name: "Proxy-Authorization")

        if let proxyAuthorization {
            head.headers.replaceOrAdd(name: "Proxy-Authorization", value: proxyAuthorization)
        }

        if overrideContentLength {
            head.headers.remove(name: "Transfer-Encoding")
            head.headers.replaceOrAdd(name: "Content-Length", value: "\(bodySize)")
        }
        return head
    }

    private func bodyBytesToSend(
        request: ProxyRequest,
        fallback: ByteBuffer,
        fallbackSize: Int,
        allocator: ByteBufferAllocator
    ) -> (ByteBuffer?, Int) {
        // Only safe to use the (possibly modified) bodyPreview when we know it's complete.
        guard !request.bodyIsTruncated else {
            return (fallbackSize > 0 ? fallback : nil, fallbackSize)
        }

        let data = request.bodyPreview ?? Data()
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        return (data.isEmpty ? nil : buffer, data.count)
    }

    private func handleLocalEndpointsIfNeeded(context: ChannelHandlerContext, head: HTTPRequestHead) -> EventLoopFuture<Bool> {
        // Match `http://proxy.pin/ssl` or `http://127.0.0.1:<port>/ssl` or `/ssl` with host header.
        let uri = head.uri
        if uri == "http://proxy.pin/ssl" || uri == "/ssl" {
            return context.eventLoop.makeFutureWithTask {
                try await self.certificateAuthority.rootCertificateDER()
            }.map { der in
                var resHead = HTTPResponseHead(version: head.version, status: .ok)
                resHead.headers.add(name: "Content-Type", value: "application/x-x509-ca-cert")
                resHead.headers.add(name: "Content-Disposition", value: "inline;filename=ProxyCoreCA.crt")
                resHead.headers.add(name: "Connection", value: "close")
                resHead.headers.add(name: "Content-Length", value: "\(der.count)")

                context.write(self.wrapOutboundOut(.head(resHead)), promise: nil)
                if head.method != .HEAD {
                    var buffer = context.channel.allocator.buffer(capacity: der.count)
                    buffer.writeBytes(der)
                    context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return true
            }.flatMapError { _ in
                self.writeError(context: context, status: .internalServerError, body: "CA unavailable")
                return context.eventLoop.makeSucceededFuture(true)
            }
        }

        if uri == "/config" {
            let body = try? JSONSerialization.data(withJSONObject: [
                "whitelist": [
                    "enabled": configuration.hostFilter.whitelistEnabled,
                    "list": configuration.hostFilter.whitelistPatterns,
                ],
                "blacklist": [
                    "enabled": configuration.hostFilter.blacklistEnabled,
                    "list": configuration.hostFilter.blacklistPatterns,
                ],
            ])
            var resHead = HTTPResponseHead(version: head.version, status: .ok)
            resHead.headers.add(name: "Content-Type", value: "application/json; charset=utf-8")
            let bytes = body ?? Data("{}".utf8)
            resHead.headers.add(name: "Content-Length", value: "\(bytes.count)")
            context.write(wrapOutboundOut(.head(resHead)), promise: nil)
            if head.method != .HEAD {
                var buffer = context.channel.allocator.buffer(capacity: bytes.count)
                buffer.writeBytes(bytes)
                context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            }
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            return context.eventLoop.makeSucceededFuture(true)
        }

        return context.eventLoop.makeSucceededFuture(false)
    }

    private func applyPreConnectInterceptors(_ endpoint: ProxyEndpoint, on eventLoop: EventLoop) -> EventLoopFuture<ProxyEndpoint> {
        var fut: EventLoopFuture<ProxyEndpoint> = eventLoop.makeSucceededFuture(endpoint)
        for interceptor in interceptors {
            fut = fut.flatMap { current in
                eventLoop.makeFutureWithTask {
                    await interceptor.preConnect(current)
                }
            }
        }
        return fut
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
        // Similar spirit to ProxyPin: timestamp + randomness.
        let t = UInt64(Date().timeIntervalSince1970 * 1000)
        let r = UInt64.random(in: 0..<UInt64.max)
        return String((t ^ r), radix: 36)
    }
}

private struct HostAndPort: Sendable {
    var host: String
    var port: Int

    var hostHeaderValue: String {
        port == 80 ? host : "\(host):\(port)"
    }

    static func parseConnectAuthority(_ authority: String) -> HostAndPort? {
        // CONNECT always uses authority-form: host:port
        let parts = authority.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        let host = String(parts[0])
        guard !host.isEmpty else { return nil }
        return HostAndPort(host: host, port: port)
    }

    static func resolveForHTTPProxyRequest(head: HTTPRequestHead, defaultPort: Int) -> HostAndPort? {
        // 1) Absolute-form URI: http://host[:port]/path
        if let url = URL(string: head.uri), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = comps.host {
            let port = comps.port ?? (comps.scheme == "https" ? 443 : defaultPort)
            return HostAndPort(host: host, port: port)
        }

        // 2) Host header
        if let hostHeader = head.headers.first(name: "Host") {
            if let parsed = parseHostHeader(hostHeader, defaultPort: defaultPort) {
                return parsed
            }
        }

        return nil
    }

    static func parseHostHeader(_ value: String, defaultPort: Int) -> HostAndPort? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let colonIndex = trimmed.lastIndex(of: ":"), colonIndex != trimmed.startIndex {
            let host = String(trimmed[..<colonIndex])
            let portStr = String(trimmed[trimmed.index(after: colonIndex)...])
            if let port = Int(portStr), !host.isEmpty {
                return HostAndPort(host: host, port: port)
            }
        }

        return HostAndPort(host: trimmed, port: defaultPort)
    }

    static func resolveForURLString(_ urlString: String, defaultPort: Int) -> HostAndPort? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let port = url.port ?? ((url.scheme == "https") ? 443 : defaultPort)
        return HostAndPort(host: host, port: port)
    }

    func requestURL(for uri: String, defaultScheme: String) -> String {
        if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return uri
        }
        let path = uri.hasPrefix("/") ? uri : "/" + uri
        return "\(defaultScheme)://\(hostHeaderValue)\(path)"
    }
}

private extension ChannelPipeline {
    func removeHTTPServerHandlersIfPresent() -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoop

        func removeIfPresent<T: ChannelHandler>(_ type: T.Type) -> EventLoopFuture<Void> {
            self.context(handlerType: T.self).flatMap { ctx in
                self.removeHandler(context: ctx)
            }.flatMapError { _ in
                eventLoop.makeSucceededFuture(())
            }
        }

        // `configureHTTPServerPipeline` installs a number of handlers; ensure we fully strip them before tunneling.
        return removeIfPresent(HTTPServerUpgradeHandler.self)
            .flatMap { removeIfPresent(HTTPServerProtocolErrorHandler.self) }
            .flatMap { removeIfPresent(NIOHTTPResponseHeadersValidator.self) }
            .flatMap { removeIfPresent(HTTPServerPipelineHandler.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPRequestDecoder>.self) }
            .flatMap { removeIfPresent(HTTPResponseEncoder.self) }
    }
}
