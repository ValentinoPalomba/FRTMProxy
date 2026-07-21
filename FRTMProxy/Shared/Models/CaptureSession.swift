import Foundation

struct CaptureSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var flowCount: Int

    var isActive: Bool { endedAt == nil }
}

struct CaptureSessionFlow: Identifiable, Equatable, Sendable {
    var flow: MitmFlow
    var note: String?
    var isBookmarked: Bool

    var id: String { flow.id }
}

struct CaptureSessionPageCursor: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let flowID: String
}

struct CaptureSessionPage: Equatable, Sendable {
    let flows: [CaptureSessionFlow]
    let nextCursor: CaptureSessionPageCursor?
    let corruptFlowIDs: [String]
}

struct CaptureSessionRetentionPolicy: Equatable, Sendable {
    var maximumSessions: Int?
    var sessionsOlderThan: Date?

    static let unlimited = CaptureSessionRetentionPolicy()
}

// MitmFlow is a value graph made exclusively of Codable Foundation value types.
// Its declaration predates strict concurrency, so the conformance lives here until
// the core model can adopt Sendable directly.
extension MitmFlow: @unchecked Sendable {}
