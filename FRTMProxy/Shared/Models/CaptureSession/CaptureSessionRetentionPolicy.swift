import Foundation

struct CaptureSessionRetentionPolicy: Equatable, Sendable {
    var maximumSessions: Int?
    var sessionsOlderThan: Date?

    static let unlimited = CaptureSessionRetentionPolicy()
}
