import Foundation

struct HARPostData: Codable, Hashable {
    var mimeType: String?
    var text: String?
    var params: [HARPostParam]?
    var encoding: String? = nil

    enum CodingKeys: String, CodingKey {
        case mimeType, text, params
        case encoding = "_encoding"
    }
}
