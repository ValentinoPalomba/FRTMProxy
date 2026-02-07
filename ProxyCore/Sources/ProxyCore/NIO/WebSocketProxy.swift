import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1
import NIOWebSocket

enum WebSocketProxy {
    static func isWebSocketUpgradeResponse(_ head: HTTPResponseHead) -> Bool {
        guard head.status.code == 101 else { return false }
        guard let upgrade = head.headers.first(name: "Upgrade")?.lowercased(), upgrade == "websocket" else {
            return false
        }
        return true
    }

    static func switchToWebSocket(
        requestID: String,
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        clientChannel: Channel,
        upstreamChannel: Channel
    ) -> EventLoopFuture<Void> {
        let upstreamEL = upstreamChannel.eventLoop

        let clientConfigured = configureClientWebSocketPipeline(
            requestID: requestID,
            configuration: configuration,
            eventBus: eventBus,
            clientChannel: clientChannel,
            upstreamChannel: upstreamChannel
        ).hop(to: upstreamEL)

        let upstreamConfigured = configureUpstreamWebSocketPipeline(
            requestID: requestID,
            configuration: configuration,
            eventBus: eventBus,
            upstreamChannel: upstreamChannel,
            clientChannel: clientChannel
        )

        return upstreamConfigured.and(clientConfigured).map { _ in
            eventBus.emit(.log("[ProxyCore] WebSocket upgraded id=\(requestID)\n"))
        }
    }

    private static func configureClientWebSocketPipeline(
        requestID: String,
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        clientChannel: Channel,
        upstreamChannel: Channel
    ) -> EventLoopFuture<Void> {
        let pipeline = clientChannel.pipeline

        return clientChannel.setOption(ChannelOptions.autoRead, value: false).flatMap {
            pipeline.removeHTTP1ServerPipelineHandlersIfPresent()
        }.flatMap {
            removeIfPresent(HTTP1FrontendHandler.self, from: pipeline)
        }.flatMap {
            removeIfPresent(HTTP1MITMFrontendHandler.self, from: pipeline)
        }.flatMap {
            addWebSocketHandlers(
                pipeline: pipeline,
                configuration: configuration,
                eventBus: eventBus,
                requestID: requestID,
                peer: upstreamChannel,
                direction: .clientToServer,
                maskPeerOutbound: true
            )
        }.flatMap {
            clientChannel.setOption(ChannelOptions.autoRead, value: true)
        }.map {
            clientChannel.read()
        }
    }

    private static func configureUpstreamWebSocketPipeline(
        requestID: String,
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        upstreamChannel: Channel,
        clientChannel: Channel
    ) -> EventLoopFuture<Void> {
        let pipeline = upstreamChannel.pipeline

        return upstreamChannel.setOption(ChannelOptions.autoRead, value: false).flatMap {
            pipeline.removeHTTP1ClientPipelineHandlersIfPresent()
        }.flatMap {
            removeIfPresent(HTTP1UpstreamHandler.self, from: pipeline)
        }.flatMap {
            removeIfPresent(HTTP1MITMUpstreamHandler.self, from: pipeline)
        }.flatMap {
            addWebSocketHandlers(
                pipeline: pipeline,
                configuration: configuration,
                eventBus: eventBus,
                requestID: requestID,
                peer: clientChannel,
                direction: .serverToClient,
                maskPeerOutbound: false
            )
        }.flatMap {
            upstreamChannel.setOption(ChannelOptions.autoRead, value: true)
        }.map {
            upstreamChannel.read()
        }
    }

    private static func addWebSocketHandlers(
        pipeline: ChannelPipeline,
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        requestID: String,
        peer: Channel,
        direction: ProxyWebSocketMessage.Direction,
        maskPeerOutbound: Bool
    ) -> EventLoopFuture<Void> {
        // Idempotency: if we're already in websocket mode, don't install duplicate codecs.
        return pipeline.context(handlerType: WebSocketRelayHandler.self).flatMap { _ in
            pipeline.eventLoop.makeSucceededFuture(())
        }.flatMapError { _ in
            pipeline.eventLoop.makeCompletedFuture {
                // Decoder -> aggregator -> relay. Encoder handles outbound frames.
                let decoder = ByteToMessageHandler(WebSocketFrameDecoder(maxFrameSize: 1 << 20))
                let encoder = WebSocketFrameEncoder()
                let aggregator = NIOWebSocketFrameAggregator(
                    minNonFinalFragmentSize: 1,
                    maxAccumulatedFrameCount: 128,
                    maxAccumulatedFrameSize: 1 << 20
                )
                let relay = WebSocketRelayHandler(
                    requestID: requestID,
                    configuration: configuration,
                    eventBus: eventBus,
                    peer: peer,
                    direction: direction,
                    maskPeerOutbound: maskPeerOutbound
                )

                try pipeline.syncOperations.addHandler(decoder, position: .last)
                try pipeline.syncOperations.addHandler(aggregator, position: .last)
                try pipeline.syncOperations.addHandler(encoder, position: .last)
                try pipeline.syncOperations.addHandler(relay, position: .last)
            }
        }
    }

    private static func removeIfPresent<T: ChannelHandler>(_ type: T.Type, from pipeline: ChannelPipeline) -> EventLoopFuture<Void> {
        let eventLoop = pipeline.eventLoop
        return pipeline.context(handlerType: T.self).flatMap { ctx in
            pipeline.removeHandler(context: ctx)
        }.flatMapError { _ in
            eventLoop.makeSucceededFuture(())
        }
    }
}

final class WebSocketRelayHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame

    private let requestID: String
    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let peer: Channel
    private let direction: ProxyWebSocketMessage.Direction
    private let maskPeerOutbound: Bool

    init(
        requestID: String,
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        peer: Channel,
        direction: ProxyWebSocketMessage.Direction,
        maskPeerOutbound: Bool
    ) {
        self.requestID = requestID
        self.configuration = configuration
        self.eventBus = eventBus
        self.peer = peer
        self.direction = direction
        self.maskPeerOutbound = maskPeerOutbound
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        if frame.opcode == .text || frame.opcode == .binary {
            let unmasked = frame.unmaskedData
            let cap = min(unmasked.readableBytes, configuration.maxCapturedBodyBytes)
            let captured = unmasked.getData(at: unmasked.readerIndex, length: cap) ?? Data()
            eventBus.emit(.webSocketMessage(ProxyWebSocketMessage(
                requestID: requestID,
                direction: direction,
                isText: frame.opcode == .text,
                data: captured
            )))
        }

        let outMask: WebSocketMaskingKey? = maskPeerOutbound ? .random() : nil
        var outData = frame.unmaskedData

        let out = WebSocketFrame(
            fin: frame.fin,
            rsv1: frame.rsv1,
            rsv2: frame.rsv2,
            rsv3: frame.rsv3,
            opcode: frame.opcode,
            maskKey: outMask,
            data: outData
        )

        peer.eventLoop.execute {
            self.peer.writeAndFlush(NIOAny(out), promise: nil)
        }

        if frame.opcode == .connectionClose {
            // Best-effort: close both sides after relaying the close frame.
            context.close(promise: nil)
            peer.eventLoop.execute {
                self.peer.close(promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.eventLoop.execute {
            self.peer.close(promise: nil)
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        peer.eventLoop.execute {
            self.peer.close(promise: nil)
        }
        context.close(promise: nil)
    }
}
