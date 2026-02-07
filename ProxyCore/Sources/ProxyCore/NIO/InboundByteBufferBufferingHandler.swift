import NIO

/// Buffers inbound `ByteBuffer` reads until the handler is removed, then replays them downstream.
///
/// This is used to avoid losing early HTTP/2 frames from an upstream TLS connection (e.g. SETTINGS)
/// while we are still reconfiguring the pipeline after ALPN negotiation.
final class InboundByteBufferBufferingHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private var pending: ByteBuffer?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = self.unwrapInboundIn(data)
        if self.pending == nil {
            self.pending = buf
        } else {
            self.pending?.writeBuffer(&buf)
        }
        // Intentionally do not forward while installed.
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        if let pending = self.pending, pending.readableBytes > 0 {
            context.fireChannelRead(self.wrapInboundOut(pending))
            context.fireChannelReadComplete()
            self.pending = nil
        }
    }
}

