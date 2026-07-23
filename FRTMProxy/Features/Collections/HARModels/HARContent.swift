import Foundation

struct HARContent: Codable, Hashable {
    var size: Int?
    var mimeType: String?
    var text: String?
    var encoding: String?
}
