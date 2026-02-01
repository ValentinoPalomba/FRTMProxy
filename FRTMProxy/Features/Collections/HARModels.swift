import Foundation

struct HARFile: Codable, Hashable {
    var log: HARLog
}

struct HARLog: Codable, Hashable {
    var version: String?
    var creator: HARCreator?
    var entries: [HAREntry]
}

struct HARCreator: Codable, Hashable {
    var name: String
    var version: String?
}

struct HAREntry: Codable, Hashable {
    var startedDateTime: Date?
    var time: Double?
    var request: HARRequest
    var response: HARResponse
}

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

struct HARHeader: Codable, Hashable {
    var name: String
    var value: String
}

struct HARQueryItem: Codable, Hashable {
    var name: String
    var value: String?
}

struct HARCookie: Codable, Hashable {
    var name: String
    var value: String
    var path: String?
    var domain: String?
    var expires: Date?
    var httpOnly: Bool?
    var secure: Bool?
}

struct HARPostData: Codable, Hashable {
    var mimeType: String?
    var text: String?
    var params: [HARPostParam]?
}

struct HARPostParam: Codable, Hashable {
    var name: String
    var value: String?
}

struct HARContent: Codable, Hashable {
    var size: Int?
    var mimeType: String?
    var text: String?
    var encoding: String?
}

