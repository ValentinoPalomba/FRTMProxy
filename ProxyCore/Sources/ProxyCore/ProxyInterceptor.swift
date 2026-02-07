import Foundation

public struct ProxyEndpoint: Sendable {
    public var host: String
    public var port: Int
    public var isTLS: Bool

    public init(host: String, port: Int, isTLS: Bool) {
        self.host = host
        self.port = port
        self.isTLS = isTLS
    }
}

public protocol ProxyInterceptor: Sendable {
    var priority: Int { get }

    func preConnect(_ endpoint: ProxyEndpoint) async -> ProxyEndpoint

    func onRequest(_ request: ProxyRequest) async -> ProxyRequest?

    func execute(_ request: ProxyRequest) async -> ProxyResponse?

    func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse?

    func onError(request: ProxyRequest?, error: any Error) async
}

public extension ProxyInterceptor {
    var priority: Int { 0 }

    func preConnect(_ endpoint: ProxyEndpoint) async -> ProxyEndpoint { endpoint }

    func onRequest(_ request: ProxyRequest) async -> ProxyRequest? { request }

    func execute(_ request: ProxyRequest) async -> ProxyResponse? { nil }

    func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? { response }

    func onError(request: ProxyRequest?, error: any Error) async {}
}
