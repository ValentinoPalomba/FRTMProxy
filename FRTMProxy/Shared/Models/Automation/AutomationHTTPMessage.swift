import Foundation

struct AutomationHTTPMessage: Codable, Equatable, Sendable {
    var url: String?
    var headers: [String: String]
    var body: String?

    init(url: String? = nil, headers: [String: String] = [:], body: String? = nil) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

struct RedactedAutomationHTTPMessage: Codable, Equatable, Sendable {
    var url: String?
    var headers: [String: String]
    var body: String?
    var bodyWasOmitted: Bool
    var bodyWasTruncated: Bool
}
