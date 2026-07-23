import Foundation

struct HARCookie: Codable, Hashable {
    var name: String
    var value: String
    var path: String?
    var domain: String?
    var expires: Date?
    var httpOnly: Bool?
    var secure: Bool?
}
