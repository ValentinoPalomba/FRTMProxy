import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOFoundationCompat
import NIOSSL

public enum ProxyEngineError: Error {
    case alreadyStarted
    case notStarted
}

public actor ProxyEngine {
    public let configuration: ProxyConfiguration
    public nonisolated let events: AsyncStream<ProxyEvent>

    private let eventBus = ProxyEventBus()
    private let interceptors: [any ProxyInterceptor]
    private let certificateAuthority: CertificateAuthority
    private let processInfoProvider = ProcessInfoProvider()
    private let trafficController = TrafficProfileController()

    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    public init(configuration: ProxyConfiguration, interceptors: [any ProxyInterceptor] = []) throws {
        self.configuration = configuration
        self.interceptors = interceptors.sorted { $0.priority < $1.priority }
        self.certificateAuthority = try CertificateAuthority(baseDirectory: configuration.paths.baseDirectory)
        self.events = eventBus.makeStream()
    }

    public func start() async throws {
        if serverChannel != nil {
            throw ProxyEngineError.alreadyStarted
        }

        try FileManager.default.createDirectory(at: configuration.paths.baseDirectory, withIntermediateDirectories: true)

        let threads = max(2, System.coreCount)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
        self.group = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [configuration, eventBus, interceptors, certificateAuthority, processInfoProvider, trafficController, group] channel in
                if let remote = configuration.remoteForward, remote.enabled {
                    // Remote forward: raw relay only (no local capture/interception).
                    return channel.pipeline.addHandler(RemoteForwardHandler(
                        remoteHost: remote.host,
                        remotePort: remote.port,
                        group: group,
                        eventBus: eventBus
                    ))
                }

                if configuration.socks5InboundEnabled {
                    // Defer installing the HTTP server pipeline until we know what protocol the client is speaking.
                    return channel.pipeline.addHandler(ProtocolSniffingHandler(
                        configuration: configuration,
                        eventBus: eventBus,
                        interceptors: interceptors,
                        certificateAuthority: certificateAuthority,
                        processInfoProvider: processInfoProvider,
                        trafficController: trafficController,
                        group: group
                    ))
                } else {
                    let handler = HTTP1FrontendHandler(
                        configuration: configuration,
                        eventBus: eventBus,
                        interceptors: interceptors,
                        certificateAuthority: certificateAuthority,
                        processInfoProvider: processInfoProvider,
                        trafficController: trafficController,
                        group: group
                    )
                    return channel.pipeline.addHTTPServerHandlers().flatMap {
                        channel.pipeline.addHandler(handler)
                    }
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        let channel = try await bootstrap.bind(host: configuration.listenHost, port: configuration.listenPort).get()
        self.serverChannel = channel

        eventBus.emit(.log("[ProxyCore] Listening on \(configuration.listenHost):\(configuration.listenPort)\n"))
    }

    public func stop() async {
        guard let serverChannel else {
            return
        }

        do {
            try await serverChannel.close().get()
        } catch {
            eventBus.emit(.log("[ProxyCore] Error closing server: \(error)\n"))
        }
        self.serverChannel = nil

        if let group {
            do {
                try await group.shutdownGracefully()
            } catch {
                eventBus.emit(.log("[ProxyCore] Error shutting down event loop: \(error)\n"))
            }
        }
        self.group = nil
        eventBus.finish()
    }

    // MARK: - Traffic shaping

    public func setTrafficProfile(_ profile: TrafficProfile) {
        trafficController.update(profile)
        eventBus.emit(.log("[ProxyCore] Traffic profile: \(profile.id)\n"))
    }

    public func currentTrafficProfile() -> TrafficProfile {
        trafficController.snapshot()
    }

    // MARK: - Replay

    /// Replays a request directly to the upstream server (no inbound client connection required).
    ///
    /// This is used by the app's "Retry" UI. The request still flows through interceptors (onRequest/execute/onResponse)
    /// so Map Local / breakpoints behave similarly to the legacy engine.
    ///
    /// - Returns: the request ID used for emitted events.
    public func replayHTTP(
        requestID: String? = nil,
        method: String,
        url: String,
        headers: [String: String],
        body: Data?
    ) async throws -> String {
        guard let group else {
            throw ProxyEngineError.notStarted
        }

        let id = requestID ?? Self.makeReplayRequestID()

        let bodySize = body?.count ?? 0
        let preview = body.flatMap { Data($0.prefix(configuration.maxCapturedBodyBytes)) }
        let bodyIsTruncated = bodySize > configuration.maxCapturedBodyBytes

        var request = ProxyRequest(
            id: id,
            httpVersion: .http1_1,
            method: method,
            url: url,
            headers: headers,
            bodyPreview: preview,
            bodyIsTruncated: bodyIsTruncated,
            rawBodySize: bodySize,
            client: ProxyClientInfo(ip: "127.0.0.1", port: nil)
        )

        eventBus.emit(.request(request))

        // onRequest interceptors
        for interceptor in interceptors {
            if let updated = await interceptor.onRequest(request) {
                request = updated
            } else {
                // Blocked request: send a synthetic response event for UI parity.
                try await emitReplayResponse(
                    ProxyResponse(
                        requestID: id,
                        httpVersion: .http1_1,
                        statusCode: 403,
                        headers: ["Content-Type": "text/plain; charset=utf-8"],
                        bodyPreview: Data("Blocked".utf8),
                        bodyIsTruncated: false,
                        rawBodySize: "Blocked".utf8.count
                    ),
                    on: group.next()
                )
                return id
            }
        }

        eventBus.emit(.request(request))

        // execute interceptors (Map Local / scripts that fully mock responses)
        for interceptor in interceptors {
            if let mocked = await interceptor.execute(request) {
                try await emitReplayResponse(mocked, on: group.next())
                return id
            }
        }

        // Resolve target + apply preConnect (DNS/hosts mapping).
        let target = try ReplayTarget(urlString: request.url)
        var endpoint = ProxyEndpoint(host: target.host, port: target.port, isTLS: target.isTLS)
        for interceptor in interceptors {
            endpoint = await interceptor.preConnect(endpoint)
        }

        // Perform upstream request.
        let client = ReplayHTTPClient(
            configuration: configuration,
            trafficController: trafficController,
            group: group
        )

        do {
            let outgoingBody: Data? = {
                // If the body is fully captured, trust the (possibly rewritten) request body.
                // Otherwise fall back to the original body payload provided by the caller.
                let candidate = request.bodyIsTruncated ? body : request.bodyPreview
                guard let candidate, !candidate.isEmpty else { return nil }
                return candidate
            }()

            var response = try await client.perform(
                request: request,
                body: outgoingBody,
                target: target,
                connectEndpoint: endpoint
            )

            // onResponse interceptors
            for interceptor in interceptors {
                if let updated = await interceptor.onResponse(request: request, response: response) {
                    response = updated
                } else {
                    // Blocked response.
                    response = ProxyResponse(
                        requestID: id,
                        httpVersion: response.httpVersion,
                        streamID: response.streamID,
                        statusCode: 403,
                        headers: ["Content-Type": "text/plain; charset=utf-8"],
                        bodyPreview: Data("Blocked".utf8),
                        bodyIsTruncated: false,
                        rawBodySize: "Blocked".utf8.count
                    )
                    break
                }
            }

            try await emitReplayResponse(response, on: group.next())
        } catch {
            eventBus.emit(.error(ProxyErrorEvent(requestID: id, message: String(describing: error))))
            throw error
        }

        return id
    }

    private func emitReplayResponse(_ response: ProxyResponse, on eventLoop: EventLoop) async throws {
        var response = response

        // Tag with the active traffic profile so the UI can show context.
        if let profileID = trafficController.profileHeaderValue() {
            response.headers["X-FRTraffic-Profile"] = profileID
        }

        if trafficController.shouldInjectPacketLoss() {
            let message = "Simulated packet loss (traffic profile)"
            let data = Data(message.utf8)
            response.statusCode = 598
            response.bodyPreview = data
            response.bodyIsTruncated = false
            response.rawBodySize = data.count
            if !response.headers.keys.contains(where: { $0.lowercased() == "content-type" }) {
                response.headers["Content-Type"] = "text/plain; charset=utf-8"
            }
        }

        let bytes = response.rawBodySize ?? (response.bodyPreview?.count ?? 0)
        try await trafficController.delayFuture(direction: .downlink, byteCount: bytes, on: eventLoop).get()
        eventBus.emit(.response(response))
    }

    // MARK: - CA management

    public func exportRootCACertificatePEM() async throws -> String {
        try await certificateAuthority.rootCertificatePEM()
    }

    public func exportRootCACertificateDER() async throws -> Data {
        try await certificateAuthority.rootCertificateDER()
    }

    public func generateNewRootCA(commonName: String = "ProxyCore CA") async throws {
        try await certificateAuthority.generateNewRootCA(commonName: commonName)
        eventBus.emit(.log("[ProxyCore] Generated new Root CA.\n"))
    }
    
    @available(*, deprecated, renamed: "generateNewRootCA(commonName:)")
    public func facci(commonName: String = "ProxyCore CA") async throws {
        try await generateNewRootCA(commonName: commonName)
    }

    public func exportRootCAPKCS12(password: String) async throws -> Data {
        try await certificateAuthority.exportRootCAPKCS12(password: password)
    }

    public func importRootCAPKCS12(_ data: Data, password: String) async throws {
        try await certificateAuthority.importRootCAPKCS12(data, password: password)
        eventBus.emit(.log("[ProxyCore] Imported Root CA from PKCS#12.\n"))
    }

    private static func makeReplayRequestID() -> String {
        let t = UInt64(Date().timeIntervalSince1970 * 1000)
        let r = UInt64.random(in: 0..<UInt64.max)
        return "replay-" + String((t ^ r), radix: 36)
    }
}

// MARK: - Replay internals

private struct ReplayTarget: Sendable {
    var scheme: String
    var host: String
    var port: Int
    var originForm: String

    var isTLS: Bool { scheme == "https" }

    init(urlString: String) throws {
        guard let comps = URLComponents(string: urlString), let host = comps.host else {
            throw ReplayHTTPClient.ReplayError.invalidURL(urlString)
        }

        let scheme = (comps.scheme ?? "http").lowercased()
        let isTLS = scheme == "https"
        let port = comps.port ?? (isTLS ? 443 : 80)

        let path = comps.percentEncodedPath.isEmpty ? "/" : comps.percentEncodedPath
        if let query = comps.percentEncodedQuery, !query.isEmpty {
            self.originForm = path + "?" + query
        } else {
            self.originForm = path
        }

        self.scheme = scheme
        self.host = host
        self.port = port
    }

    func hostHeaderValue() -> String {
        let defaultPort = isTLS ? 443 : 80
        return port == defaultPort ? host : "\(host):\(port)"
    }
}

private final class ReplayHTTPClient: @unchecked Sendable {
    enum ReplayError: Error, CustomStringConvertible {
        case invalidURL(String)
        case unsupportedScheme(String)
        case connectFailed(String)
        case proxyConnectFailed(status: Int, reason: String)
        case missingPromise(String)

        var description: String {
            switch self {
            case .invalidURL(let value): return "invalid URL: \(value)"
            case .unsupportedScheme(let scheme): return "unsupported URL scheme: \(scheme)"
            case .connectFailed(let reason): return "connect failed: \(reason)"
            case .proxyConnectFailed(let status, let reason): return "external proxy CONNECT failed (\(status)) \(reason)"
            case .missingPromise(let label): return "missing promise: \(label)"
            }
        }
    }

    private let configuration: ProxyConfiguration
    private let trafficController: TrafficProfileController
    private let group: EventLoopGroup

    init(configuration: ProxyConfiguration, trafficController: TrafficProfileController, group: EventLoopGroup) {
        self.configuration = configuration
        self.trafficController = trafficController
        self.group = group
    }

    func perform(
        request: ProxyRequest,
        body: Data?,
        target: ReplayTarget,
        connectEndpoint: ProxyEndpoint
    ) async throws -> ProxyResponse {
        switch target.scheme {
        case "http":
            return try await performHTTP1OverTCP(
                request: request,
                body: body,
                target: target,
                connectHost: configuration.externalProxy?.host ?? connectEndpoint.host,
                connectPort: configuration.externalProxy?.port ?? connectEndpoint.port,
                useAbsoluteForm: configuration.externalProxy != nil,
                proxyAuthorization: configuration.externalProxy?.basicAuthHeaderValue()
            )
        case "https":
            return try await performHTTP1OverTLS(
                request: request,
                body: body,
                target: target,
                connectEndpoint: connectEndpoint
            )
        default:
            throw ReplayError.unsupportedScheme(target.scheme)
        }
    }

    private func performHTTP1OverTCP(
        request: ProxyRequest,
        body: Data?,
        target: ReplayTarget,
        connectHost: String,
        connectPort: Int,
        useAbsoluteForm: Bool,
        proxyAuthorization: String?
    ) async throws -> ProxyResponse {
        let responsePromiseBox = NIOLockedValueBox<EventLoopPromise<ProxyResponse>?>(nil)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let promise = channel.eventLoop.makePromise(of: ProxyResponse.self)
                responsePromiseBox.withLockedValue { $0 = promise }
                let handler = ReplayHTTPResponseHandler(
                    requestID: request.id,
                    maxPreviewBytes: self.configuration.maxCapturedBodyBytes,
                    promise: promise
                )
                return channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        let channel = try await bootstrap.connect(host: connectHost, port: connectPort).get()
        guard let responsePromise = responsePromiseBox.withLockedValue({ $0 }) else {
            try? await channel.close().get()
            throw ReplayError.missingPromise("response")
        }

        let bodyData = body ?? Data()

        let head = buildRequestHead(
            request: request,
            target: target,
            bodySize: bodyData.count,
            useAbsoluteForm: useAbsoluteForm,
            proxyAuthorization: proxyAuthorization
        )

        // Apply uplink shaping before sending.
        try await trafficController.delayFuture(direction: .uplink, byteCount: bodyData.count, on: channel.eventLoop).get()

        channel.eventLoop.execute {
            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            if !bodyData.isEmpty {
                var buf = channel.allocator.buffer(capacity: bodyData.count)
                buf.writeBytes(bodyData)
                channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
            }
            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
        }

        defer { channel.eventLoop.execute { channel.close(promise: nil) } }
        return try await responsePromise.futureResult.get()
    }

    private func performHTTP1OverTLS(
        request: ProxyRequest,
        body: Data?,
        target: ReplayTarget,
        connectEndpoint: ProxyEndpoint
    ) async throws -> ProxyResponse {
        let serverHostname = target.host
        let connectHost = configuration.externalProxy?.host ?? connectEndpoint.host
        let connectPort = configuration.externalProxy?.port ?? connectEndpoint.port

        let bodyData = body ?? Data()

        // 1) Connect (optionally to external proxy)
        let channel: Channel
        if configuration.externalProxy != nil {
            channel = try await connectExternalProxyTunnel(
                proxyHost: connectHost,
                proxyPort: connectPort,
                targetHost: connectEndpoint.host,
                targetPort: connectEndpoint.port,
                proxyAuthorization: configuration.externalProxy?.basicAuthHeaderValue()
            )
        } else {
            let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            channel = try await bootstrap.connect(host: connectHost, port: connectPort).get()
        }

        // 2) TLS handshake
        let handshakePromise = channel.eventLoop.makePromise(of: String?.self)
        do {
            let sslContext = try makeClientSSLContext(alpn: ["http/1.1"])
            let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: serverHostname)

            try await channel.pipeline.addHandler(tlsHandler).flatMap {
                channel.pipeline.addHandler(TLSHandshakeNotifier(promise: handshakePromise))
            }.get()
        } catch {
            channel.eventLoop.execute { channel.close(promise: nil) }
            throw error
        }

        _ = try await handshakePromise.futureResult.get()

        // 3) HTTP client codecs + response capture
        let responsePromise = channel.eventLoop.makePromise(of: ProxyResponse.self)
        do {
            try await channel.pipeline.addHTTPClientHandlers().flatMap {
                channel.pipeline.addHandler(ReplayHTTPResponseHandler(
                    requestID: request.id,
                    maxPreviewBytes: self.configuration.maxCapturedBodyBytes,
                    promise: responsePromise
                ))
            }.get()
        } catch {
            channel.eventLoop.execute { channel.close(promise: nil) }
            throw error
        }

        let head = buildRequestHead(
            request: request,
            target: target,
            bodySize: bodyData.count,
            useAbsoluteForm: false,
            proxyAuthorization: nil
        )

        try await trafficController.delayFuture(direction: .uplink, byteCount: bodyData.count, on: channel.eventLoop).get()

        channel.eventLoop.execute {
            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            if !bodyData.isEmpty {
                var buf = channel.allocator.buffer(capacity: bodyData.count)
                buf.writeBytes(bodyData)
                channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
            }
            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
        }

        defer { channel.eventLoop.execute { channel.close(promise: nil) } }
        return try await responsePromise.futureResult.get()
    }

    private func buildRequestHead(
        request: ProxyRequest,
        target: ReplayTarget,
        bodySize: Int,
        useAbsoluteForm: Bool,
        proxyAuthorization: String?
    ) -> HTTPRequestHead {
        var head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: request.method), uri: useAbsoluteForm ? request.url : target.originForm)

        var headers = HTTPHeaders()
        for (k, v) in request.headers {
            headers.add(name: k, value: v)
        }

        if !headers.contains(name: "Host") {
            headers.add(name: "Host", value: target.hostHeaderValue())
        }

        if let proxyAuthorization, useAbsoluteForm, !headers.contains(name: "Proxy-Authorization") {
            headers.add(name: "Proxy-Authorization", value: proxyAuthorization)
        }

        headers.remove(name: "Transfer-Encoding")
        headers.replaceOrAdd(name: "Content-Length", value: "\(bodySize)")
        headers.replaceOrAdd(name: "Connection", value: "close")

        head.headers = headers
        return head
    }

    private func makeClientSSLContext(alpn: [String]) throws -> NIOSSLContext {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.renegotiationSupport = .none
        tls.applicationProtocols = alpn
        switch configuration.upstreamTLSVerification {
        case .trustAll:
            tls.certificateVerification = .none
        case .systemRoots:
            tls.certificateVerification = .fullVerification
        }
        return try NIOSSLContext(configuration: tls)
    }

    private final class HTTPProxyConnectResponseHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
        typealias InboundIn = HTTPClientResponsePart

        private let promise: EventLoopPromise<Void>
        private var status: HTTPResponseStatus?
        private var completed = false

        init(promise: EventLoopPromise<Void>) {
            self.promise = promise
        }

        private func succeedOnce() {
            guard !completed else { return }
            completed = true
            promise.succeed(())
        }

        private func failOnce(_ error: any Error) {
            guard !completed else { return }
            completed = true
            promise.fail(error)
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = unwrapInboundIn(data)
            switch part {
            case .head(let head):
                status = head.status
                if head.status.code != 200 {
                    failOnce(ReplayError.proxyConnectFailed(status: Int(head.status.code), reason: head.status.reasonPhrase))
                }
            case .body:
                break
            case .end:
                if let status, status.code == 200 {
                    succeedOnce()
                } else if status == nil {
                    failOnce(ReplayError.proxyConnectFailed(status: -1, reason: "missing response status"))
                }
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: any Error) {
            failOnce(error)
            context.close(promise: nil)
        }
    }

    private func connectExternalProxyTunnel(
        proxyHost: String,
        proxyPort: Int,
        targetHost: String,
        targetPort: Int,
        proxyAuthorization: String?
    ) async throws -> Channel {
        let connectPromiseBox = NIOLockedValueBox<EventLoopPromise<Void>?>(nil)
        let handlerBox = NIOLockedValueBox<HTTPProxyConnectResponseHandler?>(nil)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let promise = channel.eventLoop.makePromise(of: Void.self)
                connectPromiseBox.withLockedValue { $0 = promise }
                let handler = HTTPProxyConnectResponseHandler(promise: promise)
                handlerBox.withLockedValue { $0 = handler }

                return channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        let channel = try await bootstrap.connect(host: proxyHost, port: proxyPort).get()
        guard let promise = connectPromiseBox.withLockedValue({ $0 }) else {
            channel.eventLoop.execute { channel.close(promise: nil) }
            throw ReplayError.missingPromise("connect")
        }

        var head = HTTPRequestHead(version: .http1_1, method: .CONNECT, uri: "\(targetHost):\(targetPort)")
        head.headers.add(name: "Host", value: "\(targetHost):\(targetPort)")
        head.headers.add(name: "Proxy-Connection", value: "keep-alive")
        if let proxyAuthorization {
            head.headers.add(name: "Proxy-Authorization", value: proxyAuthorization)
        }

        channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        do {
            try await promise.futureResult.get()
        } catch {
            channel.eventLoop.execute { channel.close(promise: nil) }
            throw error
        }

        let connectHandler = handlerBox.withLockedValue { $0 }
        do {
            try await channel.pipeline.removeHTTP1ClientPipelineHandlersIfPresent().flatMap {
                if let connectHandler {
                    return channel.pipeline.removeHandler(connectHandler).flatMapError { error in
                        if let e = error as? ChannelPipelineError, (e == .notFound || e == .alreadyRemoved) {
                            return channel.eventLoop.makeSucceededFuture(())
                        }
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                return channel.eventLoop.makeSucceededFuture(())
            }.get()
        } catch {
            channel.eventLoop.execute { channel.close(promise: nil) }
            throw error
        }

        return channel
    }
}

private final class ReplayHTTPResponseHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let requestID: String
    private let maxPreviewBytes: Int
    private let promise: EventLoopPromise<ProxyResponse>

    private var head: HTTPResponseHead?
    private var bodyPreview = Data()
    private var bodySize: Int = 0
    private var completed = false

    init(requestID: String, maxPreviewBytes: Int, promise: EventLoopPromise<ProxyResponse>) {
        self.requestID = requestID
        self.maxPreviewBytes = maxPreviewBytes
        self.promise = promise
    }

    private func completeOnce(_ result: Result<ProxyResponse, Error>) {
        guard !completed else { return }
        completed = true
        switch result {
        case .success(let response):
            promise.succeed(response)
        case .failure(let error):
            promise.fail(error)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            self.head = head
            bodyPreview.removeAll(keepingCapacity: true)
            bodySize = 0

        case .body(var buffer):
            let readable = buffer.readableBytes
            bodySize += readable
            if bodyPreview.count < maxPreviewBytes {
                let toCopy = min(maxPreviewBytes - bodyPreview.count, readable)
                if let bytes = buffer.readBytes(length: toCopy) {
                    bodyPreview.append(contentsOf: bytes)
                }
            }

        case .end:
            guard let head else {
                completeOnce(.failure(ReplayHTTPClient.ReplayError.connectFailed("missing response head")))
                return
            }
            let response = ProxyResponse(
                requestID: requestID,
                httpVersion: .http1_1,
                statusCode: Int(head.status.code),
                headers: head.headers.asFlatDictionary(),
                bodyPreview: bodyPreview,
                bodyIsTruncated: bodySize > maxPreviewBytes,
                rawBodySize: bodySize
            )
            completeOnce(.success(response))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        completeOnce(.failure(error))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completeOnce(.failure(ChannelError.eof))
        }
        context.fireChannelInactive()
    }
}
