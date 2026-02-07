import NIO

extension ChannelPipeline {
    /// Convenience wrapper around `configureHTTPServerPipeline(withErrorHandling:)`.
    func addHTTPServerHandlers() -> EventLoopFuture<Void> {
        self.configureHTTPServerPipeline(withErrorHandling: true)
    }
}

