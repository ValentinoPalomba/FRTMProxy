import Foundation

struct MapRuleRequest: Hashable, Codable, Sendable {
    var method: String
    var url: String
    var headers: [String: String]
    var body: String?

    init(method: String, url: String, headers: [String: String] = [:], body: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}
