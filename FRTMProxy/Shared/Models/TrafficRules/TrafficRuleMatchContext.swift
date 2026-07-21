import Foundation

struct TrafficRuleMatchContext: Hashable, Sendable {
    var scheme: String
    var host: String
    var path: String
    var method: String
    var url: String
    var headers: [String: String]
    var body: String?

    init(
        scheme: String,
        host: String,
        path: String,
        method: String,
        url: String,
        headers: [String: String] = [:],
        body: String? = nil
    ) {
        self.scheme = scheme
        self.host = host
        self.path = path.isEmpty ? "/" : path
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}
