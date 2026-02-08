import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOHTTP2
import NIOSSL

final class ConnectTunnelHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let certificateAuthority: CertificateAuthority
    private let processInfoProvider: ProcessInfoProvider
    private let trafficController: TrafficProfileController
    private let group: EventLoopGroup

    private let targetHost: String
    private let targetPort: Int
    private let connectRequestID: String

    private var upstreamChannel: Channel?
    private var pendingClientBytes: ByteBuffer?
    private var isEstablishing: Bool = false
    private let maxClientHelloBytes = 16 * 1024

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        certificateAuthority: CertificateAuthority,
        processInfoProvider: ProcessInfoProvider,
        trafficController: TrafficProfileController,
        group: EventLoopGroup,
        targetHost: String,
        targetPort: Int,
        connectRequestID: String
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.certificateAuthority = certificateAuthority
        self.processInfoProvider = processInfoProvider
        self.trafficController = trafficController
        self.group = group
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.connectRequestID = connectRequestID
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        if upstreamChannel == nil {
            if pendingClientBytes == nil {
                pendingClientBytes = buffer
            } else {
                pendingClientBytes?.writeBuffer(&buffer)
            }

            if !isEstablishing {
                // If MITM is enabled, wait until we have enough bytes to parse a TLS ClientHello.
                if configuration.enableMITM {
                    guard let pending = pendingClientBytes else { return }

                    // Need at least a TLS record header + handshake header to decide.
                    if pending.readableBytes < 11 {
                        return
                    }

                    // If the client isn't starting TLS, fall back to a raw tunnel.
                    guard TLSClientHelloParser.isTLSClientHello(pending) else {
                        isEstablishing = true
                        startRawTunnel(context: context)
                        return
                    }

                    // Avoid buffering unbounded amounts of data.
                    if pending.readableBytes > maxClientHelloBytes {
                        eventBus.emit(.log("[ProxyCore] ClientHello exceeded \(maxClientHelloBytes) bytes, falling back to raw tunnel.\n"))
                        isEstablishing = true
                        startRawTunnel(context: context)
                        return
                    }

                    // Start MITM once we can fully parse SNI/ALPN.
                    if let hello = TLSClientHelloParser.parse(pending) {
                        isEstablishing = true
                        let hostForFilter = hello.sniHost ?? self.targetHost
                        if self.configuration.hostFilter.shouldFilter(host: hostForFilter) {
                            self.eventBus.emit(.log("[ProxyCore] HostFilter bypass MITM \(hostForFilter)\n"))
                            startRawTunnel(context: context)
                        } else {
                            startMITM(context: context, clientHello: hello)
                        }
                    }
                } else {
                    isEstablishing = true
                    startRawTunnel(context: context)
                }
            }
            return
        }

        // Tunnel established: Relay client->upstream.
        if let upstreamChannel {
            upstreamChannel.eventLoop.execute {
                upstreamChannel.writeAndFlush(buffer, promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        upstreamChannel?.close(promise: nil)
    }

    private func startRawTunnel(context: ChannelHandlerContext) {
        // Capture the client channel while we're on its event loop. Accessing `context.channel`
        // from another event loop (e.g. the upstream connect future's event loop) will trap.
        let clientChannel = context.channel

        let endpoint = ProxyEndpoint(host: targetHost, port: targetPort, isTLS: true)
        applyPreConnectInterceptors(endpoint, on: context.eventLoop).flatMap { updatedEndpoint in
            let connectFuture: EventLoopFuture<Channel>
            if self.configuration.externalProxy != nil {
                connectFuture = self.connectExternalProxyTunnel(targetHost: updatedEndpoint.host, targetPort: updatedEndpoint.port)
            } else {
                let bootstrap = ClientBootstrap(group: self.group)
                    .channelInitializer { channel in
                        channel.eventLoop.makeSucceededFuture(())
                    }
                connectFuture = bootstrap.connect(host: updatedEndpoint.host, port: updatedEndpoint.port)
            }

            return connectFuture.flatMap { upstream in
                // Ensure upstream relays back to the client (external proxy path adds relay only after CONNECT).
                upstream.pipeline.addHandler(RelayHandler(peer: clientChannel), position: .last).flatMapError { error in
                    if let e = error as? ChannelPipelineError, (e == .alreadyRemoved || e == .notFound) {
                        return upstream.eventLoop.makeSucceededFuture(())
                    }
                    return upstream.eventLoop.makeFailedFuture(error)
                }.map {
                    upstream
                }
            }
        }.whenComplete { result in
            switch result {
            case .success(let upstream):
                self.upstreamChannel = upstream

                // Swap this handler out for a pure relay.
                clientChannel.pipeline.addHandler(RelayHandler(peer: upstream)).flatMap {
                    clientChannel.pipeline.removeHandler(self)
                }.whenComplete { _ in
                    if var pending = self.pendingClientBytes {
                        self.pendingClientBytes = nil
                        upstream.eventLoop.execute {
                            upstream.writeAndFlush(pending, promise: nil)
                        }
                    }
                }

            case .failure(let error):
                self.eventBus.emit(.log("[ProxyCore] Tunnel connect failed: \(error)\n"))
                clientChannel.close(promise: nil)
            }
        }
    }

    private func startMITM(context: ChannelHandlerContext, clientHello: TLSClientHelloInfo) {
        let clientChannel = context.channel
        let clientEventLoop = context.eventLoop

        let pendingBytes = pendingClientBytes ?? clientChannel.allocator.buffer(capacity: 0)
        pendingClientBytes = nil

        let sniHost = clientHello.sniHost ?? targetHost

        // Negotiate ALPN based on (a) what the client offered and (b) what we support.
        let supported = configuration.enableHTTP2 ? ["h2", "http/1.1"] : ["http/1.1"]
        var offeredUpstream: [String]
        if clientHello.alpnProtocols.isEmpty {
            offeredUpstream = ["http/1.1"]
        } else {
            offeredUpstream = supported.filter { clientHello.alpnProtocols.contains($0) }
            if offeredUpstream.isEmpty {
                offeredUpstream = ["http/1.1"]
            }
        }

        // Stop reads while we mutate the pipeline.
        let endpoint = ProxyEndpoint(host: sniHost, port: targetPort, isTLS: true)
        clientChannel.setOption(ChannelOptions.autoRead, value: false).flatMap {
            self.applyPreConnectInterceptors(endpoint, on: clientEventLoop)
        }.flatMap { updatedEndpoint in
            self.connectUpstreamTLS(serverHostname: sniHost, connectHost: updatedEndpoint.host, connectPort: updatedEndpoint.port, alpn: offeredUpstream)
        }.flatMap { upstream, negotiated, upstreamBuffering in
            self.upstreamChannel = upstream

            let selected = negotiated ?? "http/1.1"
            let serverALPN = negotiated.map { [$0] } ?? []

            // Prepare the server-side TLS context (leaf cert).
            return clientEventLoop.makeFutureWithTask {
                try await self.certificateAuthority.serverTLSContext(
                    for: CertificateAuthority.LeafConfig(host: sniHost, alpnProtocols: serverALPN)
                )
            }.flatMap { serverTLSContext in
                // Configure upstream application pipeline first.
                return self.configureUpstreamApplicationPipeline(
                    upstream: upstream,
                    selectedProtocol: selected,
                    clientChannel: clientChannel,
                    authorityFallback: self.authorityFallback(),
                    bufferingHandler: upstreamBuffering
                ).hop(to: clientEventLoop).flatMap { upstreamMode in
                    // Configure client pipeline (TLS server + HTTP/1.1 or HTTP/2).
                    return self.configureClientMITMPipeline(
                        clientContext: context,
                        serverTLSContext: serverTLSContext,
                        selectedProtocol: selected,
                        upstream: upstream,
                        upstreamMode: upstreamMode
                    ).flatMap {
                        // Feed the buffered ClientHello into the new TLS handler.
                        clientChannel.pipeline.fireChannelRead(pendingBytes)
                        clientChannel.pipeline.fireChannelReadComplete()

                        // Resume reads.
                        return clientChannel.setOption(ChannelOptions.autoRead, value: true)
                    }.map {
                        context.read()
                    }
                }
            }
        }.whenFailure { error in
            self.eventBus.emit(.log("[ProxyCore] MITM failed: \(String(reflecting: error))\n"))
            if let upstream = self.upstreamChannel {
                upstream.eventLoop.execute {
                    upstream.close(promise: nil)
                }
            }
            context.close(promise: nil)
        }
    }

    private enum UpstreamMode {
        case http1(session: HTTP1MITMSession)
        case h2(multiplexer: HTTP2StreamMultiplexer)
    }

    private enum MITMError: Error {
        case missingHandshakeFuture
        case unexpectedUpstreamMode
    }

    private enum ExternalProxyError: Error, CustomStringConvertible {
        case connectFailed(status: Int, reason: String)

        var description: String {
            switch self {
            case .connectFailed(let status, let reason):
                return "External proxy CONNECT failed (\(status)) \(reason)"
            }
        }
    }

    private func authorityFallback() -> String {
        targetPort == 443 ? targetHost : "\(targetHost):\(targetPort)"
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
                    failOnce(ExternalProxyError.connectFailed(status: Int(head.status.code), reason: head.status.reasonPhrase))
                }

            case .body:
                break

            case .end:
                if let status, status.code == 200 {
                    succeedOnce()
                } else if status == nil {
                    failOnce(ExternalProxyError.connectFailed(status: -1, reason: "missing response status"))
                }
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: any Error) {
            failOnce(error)
            context.close(promise: nil)
        }
    }

    private func connectExternalProxyTunnel(targetHost: String, targetPort: Int) -> EventLoopFuture<Channel> {
        guard let proxy = configuration.externalProxy else {
            return group.next().makeFailedFuture(ExternalProxyError.connectFailed(status: -1, reason: "no external proxy configured"))
        }

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

        return bootstrap.connect(host: proxy.host, port: proxy.port).flatMap { channel in
            guard let promise = connectPromiseBox.withLockedValue({ $0 }) else {
                return channel.eventLoop.makeFailedFuture(ExternalProxyError.connectFailed(status: -1, reason: "missing CONNECT promise"))
            }

            // Send CONNECT request to the external proxy.
            var head = HTTPRequestHead(version: .http1_1, method: .CONNECT, uri: "\(targetHost):\(targetPort)")
            head.headers.add(name: "Host", value: "\(targetHost):\(targetPort)")
            head.headers.add(name: "Proxy-Connection", value: "keep-alive")
            if let auth = proxy.basicAuthHeaderValue() {
                head.headers.add(name: "Proxy-Authorization", value: auth)
            }

            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

            return promise.futureResult.flatMap {
                // CONNECT established: drop HTTP codecs so the channel becomes a raw tunnel.
                let connectHandler = handlerBox.withLockedValue { $0 }
                return channel.pipeline.removeHTTP1ClientPipelineHandlersIfPresent().flatMap {
                    if let connectHandler {
                        return channel.pipeline.removeHandler(connectHandler).flatMapError { error in
                            if let e = error as? ChannelPipelineError, (e == .notFound || e == .alreadyRemoved) {
                                return channel.eventLoop.makeSucceededFuture(())
                            }
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    }
                    return channel.eventLoop.makeSucceededFuture(())
                }.map {
                    channel
                }
            }
        }
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

    private func connectUpstreamTLS(
        serverHostname: String,
        connectHost: String,
        connectPort: Int,
        alpn: [String]
    ) -> EventLoopFuture<(Channel, String?, InboundByteBufferBufferingHandler?)> {
        do {
            var tls = TLSConfiguration.makeClientConfiguration()
            tls.renegotiationSupport = .none
            tls.applicationProtocols = alpn
            switch configuration.upstreamTLSVerification {
            case .trustAll:
                tls.certificateVerification = .none
            case .systemRoots:
                tls.certificateVerification = .fullVerification
            }

            let sslContext = try NIOSSLContext(configuration: tls)

            let negotiatedBox = NIOLockedValueBox<EventLoopFuture<String?>?>(nil)
            let bufferingBox = NIOLockedValueBox<InboundByteBufferBufferingHandler?>(nil)

            func installTLS(on channel: Channel) -> EventLoopFuture<Void> {
                let promise = channel.eventLoop.makePromise(of: String?.self)
                negotiatedBox.withLockedValue { $0 = promise.futureResult }
                let buffering = InboundByteBufferBufferingHandler()
                bufferingBox.withLockedValue { $0 = buffering }

                do {
                    let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: serverHostname)
                    return channel.pipeline.addHandler(tlsHandler).flatMap {
                        channel.pipeline.addHandler(TLSHandshakeNotifier(promise: promise))
                    }.flatMap {
                        // Buffer any inbound plaintext until we have installed the HTTP/1 or HTTP/2 handlers.
                        channel.pipeline.addHandler(buffering, position: .last)
                    }.flatMapError { error in
                        // Ensure the handshake promise is completed even if channel init fails.
                        promise.fail(error)
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                } catch {
                    promise.fail(error)
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

            let connectFuture: EventLoopFuture<Channel>
            if configuration.externalProxy != nil {
                // Establish an HTTP CONNECT tunnel through the external proxy, then run TLS inside it.
                connectFuture = connectExternalProxyTunnel(targetHost: connectHost, targetPort: connectPort).flatMap { channel in
                    installTLS(on: channel).map { channel }
                }
            } else {
                let bootstrap = ClientBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        installTLS(on: channel)
                    }
                connectFuture = bootstrap.connect(host: connectHost, port: connectPort)
            }

            return connectFuture.flatMap { channel in
                guard let negotiatedFuture = negotiatedBox.withLockedValue({ $0 }) else {
                    return channel.eventLoop.makeFailedFuture(MITMError.missingHandshakeFuture)
                }
                let buffering = bufferingBox.withLockedValue { $0 }
                return negotiatedFuture.map { negotiated in
                    (channel, negotiated, buffering)
                }
            }
        } catch {
            return group.next().makeFailedFuture(error)
        }
    }

    private func configureUpstreamApplicationPipeline(
        upstream: Channel,
        selectedProtocol: String,
        clientChannel: Channel,
        authorityFallback: String,
        bufferingHandler: InboundByteBufferBufferingHandler?
    ) -> EventLoopFuture<UpstreamMode> {
        func removeBufferingIfNeeded() -> EventLoopFuture<Void> {
            guard let bufferingHandler else {
                return upstream.eventLoop.makeSucceededFuture(())
            }
            return upstream.pipeline.removeHandler(bufferingHandler).flatMapError { error in
                // If the handler vanished due to connection teardown, ignore.
                if let e = error as? ChannelPipelineError, (e == .notFound || e == .alreadyRemoved) {
                    return upstream.eventLoop.makeSucceededFuture(())
                }
                return upstream.eventLoop.makeFailedFuture(error)
            }
        }

        if selectedProtocol == "h2", configuration.enableHTTP2 {
            return upstream.configureHTTP2Pipeline(mode: .client, inboundStreamInitializer: { streamChannel in
                // Server push is not supported: close.
                streamChannel.close(promise: nil)
                return streamChannel.eventLoop.makeSucceededFuture(())
            }).flatMap { mux in
                removeBufferingIfNeeded().flatMap {
                // Close the client if the upstream connection dies.
                upstream.pipeline.addHandler(ErrorLoggingHandler(eventBus: self.eventBus, label: "upstream-h2"), position: .last).flatMap {
                    upstream.pipeline.addHandler(PeerCloseHandler(peer: clientChannel), position: .last)
                }.map {
                    .h2(multiplexer: mux)
                }
                }
            }
        }

        let session = HTTP1MITMSession()
        return upstream.pipeline.addHTTPClientHandlers().flatMap {
            upstream.pipeline.addHandler(
                HTTP1MITMUpstreamHandler(
                    configuration: self.configuration,
                    eventBus: self.eventBus,
                    interceptors: self.interceptors,
                    trafficController: self.trafficController,
                    clientChannel: clientChannel,
                    session: session
                ),
                position: .last
            )
        }.flatMap {
            removeBufferingIfNeeded()
        }.flatMap {
            upstream.pipeline.addHandler(PeerCloseHandler(peer: clientChannel), position: .last)
        }.map {
            .http1(session: session)
        }
    }

    private func configureClientMITMPipeline(
        clientContext: ChannelHandlerContext,
        serverTLSContext: NIOSSLContext,
        selectedProtocol: String,
        upstream: Channel,
        upstreamMode: UpstreamMode
    ) -> EventLoopFuture<Void> {
        let pipeline = clientContext.channel.pipeline

        // Remove this tunnel handler before installing decoders/codecs.
        let removeSelf = pipeline.removeHandler(self).flatMapError { error in
            if let e = error as? ChannelPipelineError, (e == .notFound || e == .alreadyRemoved) {
                return clientContext.eventLoop.makeSucceededFuture(())
            }
            return clientContext.eventLoop.makeFailedFuture(error)
        }

        return removeSelf.flatMap {
            pipeline.addHandler(NIOSSLServerHandler(context: serverTLSContext), position: .first)
        }.flatMap {
            // Close upstream when the client disconnects.
            pipeline.addHandler(PeerCloseHandler(peer: upstream), position: .last)
        }.flatMap {
            if selectedProtocol == "h2", self.configuration.enableHTTP2, case .h2(let upstreamMux) = upstreamMode {
                // HTTP/2 end-to-end: configure parent channel with HTTP/2 and configure stream channels.
                return clientContext.channel.configureHTTP2Pipeline(mode: .server, inboundStreamInitializer: { streamChannel in
                    streamChannel.eventLoop.makeCompletedFuture {
                        try streamChannel.pipeline.syncOperations.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                        try streamChannel.pipeline.syncOperations.addHandler(
                            HTTP2MITMClientStreamHandler(
                                configuration: self.configuration,
                                eventBus: self.eventBus,
                                interceptors: self.interceptors,
                                processInfoProvider: self.processInfoProvider,
                                trafficController: self.trafficController,
                                upstreamMultiplexer: upstreamMux,
                                authorityFallback: self.authorityFallback()
                            )
                        )
                    }
                }).flatMap { _ in
                    pipeline.addHandler(ErrorLoggingHandler(eventBus: self.eventBus, label: "client-h2"), position: .last)
                }
            }

            // Default to HTTP/1.1 inside the tunnel.
            guard case .http1(let session) = upstreamMode else {
                return clientContext.eventLoop.makeFailedFuture(MITMError.unexpectedUpstreamMode)
            }

            return pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                pipeline.addHandler(
                    HTTP1MITMFrontendHandler(
                        configuration: self.configuration,
                        eventBus: self.eventBus,
                        interceptors: self.interceptors,
                        processInfoProvider: self.processInfoProvider,
                        trafficController: self.trafficController,
                        upstreamChannel: upstream,
                        session: session,
                        targetHost: self.targetHost,
                        targetPort: self.targetPort
                    ),
                    position: .last
                )
            }
        }
    }
}

final class RelayHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let peer: Channel

    init(peer: Channel) {
        self.peer = peer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        peer.eventLoop.execute {
            self.peer.writeAndFlush(buffer, promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        context.close(promise: nil)
        peer.eventLoop.execute {
            self.peer.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.eventLoop.execute {
            self.peer.close(promise: nil)
        }
    }
}
