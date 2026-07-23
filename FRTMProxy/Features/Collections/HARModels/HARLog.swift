import Foundation

struct HARLog: Codable, Hashable {
    var version: String?
    var creator: HARCreator?
    var entries: [HAREntry]
}
