import NIO

/// Closes the `peer` channel when the current channel becomes inactive.
final class PeerCloseHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let peer: Channel

    init(peer: Channel) {
        self.peer = peer
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

