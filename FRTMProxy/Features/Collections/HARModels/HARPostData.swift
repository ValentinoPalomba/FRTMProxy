import Foundation

struct HARPostData: Codable, Hashable {
    var mimeType: String?
    var text: String?
    var params: [HARPostParam]?
}
