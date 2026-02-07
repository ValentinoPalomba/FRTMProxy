import Foundation
import NIOConcurrencyHelpers

final class ProxyEventBus: @unchecked Sendable {
    private let lock = NIOLock()
    private var continuation: AsyncStream<ProxyEvent>.Continuation?

    func makeStream() -> AsyncStream<ProxyEvent> {
        AsyncStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
            }
        }
    }

    func emit(_ event: ProxyEvent) {
        lock.withLock {
            continuation?.yield(event)
        }
    }

    func finish() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }
}
