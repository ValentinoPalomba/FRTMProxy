import Foundation

struct BreakpointRequestPayload: Codable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?
}
