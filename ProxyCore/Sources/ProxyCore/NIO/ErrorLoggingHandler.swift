import NIO

/// Emits pipeline errors to the event bus to aid debugging (and to avoid silent HTTP/2 failures).
final class ErrorLoggingHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let eventBus: ProxyEventBus
    private let label: String

    init(eventBus: ProxyEventBus, label: String) {
        self.eventBus = eventBus
        self.label = label
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        eventBus.emit(.log("[ProxyCore] \(label) error: \(String(reflecting: error))\n"))
        context.close(promise: nil)
    }
}
