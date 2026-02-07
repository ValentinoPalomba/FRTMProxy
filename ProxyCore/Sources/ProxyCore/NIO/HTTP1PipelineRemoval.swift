import NIO
import NIOHTTP1

extension ChannelPipeline {
    /// Best-effort removal of handlers added by `configureHTTPServerPipeline(withErrorHandling:)`.
    func removeHTTP1ServerPipelineHandlersIfPresent() -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoop

        func removeIfPresent<T: ChannelHandler>(_ type: T.Type) -> EventLoopFuture<Void> {
            self.context(handlerType: T.self).flatMap { ctx in
                self.removeHandler(context: ctx)
            }.flatMapError { _ in
                eventLoop.makeSucceededFuture(())
            }
        }

        return removeIfPresent(HTTPServerUpgradeHandler.self)
            .flatMap { removeIfPresent(HTTPServerProtocolErrorHandler.self) }
            .flatMap { removeIfPresent(NIOHTTPResponseHeadersValidator.self) }
            .flatMap { removeIfPresent(HTTPServerPipelineHandler.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPRequestDecoder>.self) }
            .flatMap { removeIfPresent(HTTPResponseEncoder.self) }
    }

    /// Best-effort removal of handlers added by `addHTTPClientHandlers()`.
    func removeHTTP1ClientPipelineHandlersIfPresent() -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoop

        func removeIfPresent<T: ChannelHandler>(_ type: T.Type) -> EventLoopFuture<Void> {
            self.context(handlerType: T.self).flatMap { ctx in
                self.removeHandler(context: ctx)
            }.flatMapError { _ in
                eventLoop.makeSucceededFuture(())
            }
        }

        return removeIfPresent(NIOHTTPClientUpgradeHandler.self)
            .flatMap { removeIfPresent(NIOHTTPRequestHeadersValidator.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPResponseDecoder>.self) }
            .flatMap { removeIfPresent(HTTPRequestEncoder.self) }
    }
}

