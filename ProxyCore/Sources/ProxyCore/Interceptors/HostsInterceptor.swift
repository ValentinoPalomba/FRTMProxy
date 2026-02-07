import Foundation

/// ProxyPin-style Hosts mapping (`hosts.json`).
public struct HostsInterceptor: ProxyInterceptor {
    public let store: HostsStore

    public init(store: HostsStore) {
        self.store = store
    }

    public var priority: Int { -1000 }

    public func preConnect(_ endpoint: ProxyEndpoint) async -> ProxyEndpoint {
        if let mapped = await store.resolve(host: endpoint.host) {
            return ProxyEndpoint(host: mapped, port: endpoint.port, isTLS: endpoint.isTLS)
        }
        return endpoint
    }
}

