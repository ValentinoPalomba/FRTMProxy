import Foundation
import NIO

/// Sniffs the first bytes of an inbound connection and decides whether the client
/// is speaking HTTP proxy (default) or SOCKS5 (optional).
final class ProtocolSniffingHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let certificateAuthority: CertificateAuthority
    private let processInfoProvider: ProcessInfoProvider
    private let group: EventLoopGroup

    private var pending: ByteBuffer?
    private var decided = false

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
        var buffer = unwrapInboundIn(data)
        if pending == nil {
            pending = buffer
        } else {
            pending?.writeBuffer(&buffer)
        }

        guard !decided, let pending, pending.readableBytes >= 1 else {
            return
        }
        decided = true

        // Decide based on the very first byte:
        // - 0x05 => SOCKS5
        // - otherwise => HTTP proxy
        let first = pending.getInteger(at: pending.readerIndex, as: UInt8.self) ?? 0
        if configuration.socks5InboundEnabled, first == 0x05 {
            switchToSOCKS5(context: context, initial: pending)
        } else {
            switchToHTTP(context: context, initial: pending)
        }

        self.pending = nil
    }

    private func switchToHTTP(context: ChannelHandlerContext, initial: ByteBuffer) {
        let channel = context.channel
        let pipeline = channel.pipeline

        let handler = HTTP1FrontendHandler(
            configuration: configuration,
            eventBus: eventBus,
            interceptors: interceptors,
            certificateAuthority: certificateAuthority,
            processInfoProvider: processInfoProvider,
            group: group
        )

        pipeline.addHTTPServerHandlers().flatMap {
            pipeline.addHandler(handler, position: .last)
        }.flatMap {
            pipeline.removeHandler(self)
        }.whenComplete { _ in
            // Re-inject buffered bytes.
            channel.pipeline.fireChannelRead(initial)
            channel.pipeline.fireChannelReadComplete()
        }
    }

    private func switchToSOCKS5(context: ChannelHandlerContext, initial: ByteBuffer) {
        let channel = context.channel
        let pipeline = channel.pipeline

        let handler = Socks5HandshakeHandler(
            configuration: configuration,
            eventBus: eventBus,
            interceptors: interceptors,
            certificateAuthority: certificateAuthority,
            processInfoProvider: processInfoProvider,
            group: group
        )

        pipeline.addHandler(handler, position: .last).flatMap {
            pipeline.removeHandler(self)
        }.whenComplete { _ in
            // Re-inject buffered bytes.
            channel.pipeline.fireChannelRead(initial)
            channel.pipeline.fireChannelReadComplete()
        }
    }
}
