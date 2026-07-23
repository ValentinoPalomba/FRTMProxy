import Foundation

struct CaptureSessionPageCursor: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let flowID: String
}
