import Foundation
import NIO

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
            .childChannelInitializer { [configuration, eventBus, interceptors, certificateAuthority, processInfoProvider, group] channel in
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
                        group: group
                    ))
                } else {
                    let handler = HTTP1FrontendHandler(
                        configuration: configuration,
                        eventBus: eventBus,
                        interceptors: interceptors,
                        certificateAuthority: certificateAuthority,
                        processInfoProvider: processInfoProvider,
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

    // MARK: - CA management

    public func exportRootCACertificatePEM() async throws -> String {
        try await certificateAuthority.rootCertificatePEM()
    }

    public func exportRootCACertificateDER() async throws -> Data {
        try await certificateAuthority.rootCertificateDER()
    }

    public func facci(commonName: String = "ProxyCore CA") async throws {
        try await certificateAuthority.generateNewRootCA(commonName: commonName)
        eventBus.emit(.log("[ProxyCore] Generated new Root CA.\n"))
    }

    public func exportRootCAPKCS12(password: String) async throws -> Data {
        try await certificateAuthority.exportRootCAPKCS12(password: password)
    }

    public func importRootCAPKCS12(_ data: Data, password: String) async throws {
        try await certificateAuthority.importRootCAPKCS12(data, password: password)
        eventBus.emit(.log("[ProxyCore] Imported Root CA from PKCS#12.\n"))
    }
}
