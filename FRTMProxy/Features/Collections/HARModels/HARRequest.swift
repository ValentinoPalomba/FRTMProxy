import Foundation

struct HARRequest: Codable, Hashable {
    var method: String?
    var url: String
    var httpVersion: String?
    var headers: [HARHeader]?
    var queryString: [HARQueryItem]?
    var cookies: [HARCookie]?
    var headersSize: Int?
    var bodySize: Int?
    var postData: HARPostData?
}
