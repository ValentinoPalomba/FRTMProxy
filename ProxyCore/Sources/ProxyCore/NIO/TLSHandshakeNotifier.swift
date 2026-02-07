import NIO
import NIOTLS

/// Bridges the `TLSUserEvent.handshakeCompleted` ALPN result into a promise.
final class TLSHandshakeNotifier: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let promise: EventLoopPromise<String?>
    private var completed = false

    init(promise: EventLoopPromise<String?>) {
        self.promise = promise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case .handshakeCompleted(let negotiatedProtocol) = event as? TLSUserEvent {
            if !completed {
                completed = true
                promise.succeed(negotiatedProtocol)
                context.pipeline.removeHandler(self, promise: nil)
            }
        }

        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if !completed {
            completed = true
            promise.fail(error)
        }
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completed = true
            promise.fail(ChannelError.eof)
        }
        context.fireChannelInactive()
    }
}
