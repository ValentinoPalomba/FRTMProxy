import Foundation

public struct RequestBlockInterceptor: ProxyInterceptor {
    public let store: RequestBlockStore

    public init(store: RequestBlockStore) {
        self.store = store
    }

    public var priority: Int { 1000 }

    public func onRequest(_ request: ProxyRequest) async -> ProxyRequest? {
        if await store.isBlocked(url: request.url, type: .blockRequest) {
            return nil
        }
        return request
    }

    public func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        if await store.isBlocked(url: request.url, type: .blockResponse) {
            return nil
        }
        return response
    }
}
