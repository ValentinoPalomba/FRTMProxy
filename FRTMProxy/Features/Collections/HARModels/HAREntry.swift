import Foundation

struct HAREntry: Codable, Hashable {
    var startedDateTime: Date?
    var time: Double?
    var request: HARRequest
    var response: HARResponse
}
