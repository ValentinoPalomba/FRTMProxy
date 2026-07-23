import Foundation

struct HARResponse: Codable, Hashable {
    var status: Int
    var statusText: String?
    var httpVersion: String?
    var headers: [HARHeader]?
    var cookies: [HARCookie]?
    var content: HARContent?
    var redirectURL: String?
    var headersSize: Int?
    var bodySize: Int?
}
