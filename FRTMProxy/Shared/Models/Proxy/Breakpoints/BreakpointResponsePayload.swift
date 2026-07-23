import Foundation

struct BreakpointResponsePayload: Codable {
    let status: Int
    let headers: [String: String]
    let body: String
}
