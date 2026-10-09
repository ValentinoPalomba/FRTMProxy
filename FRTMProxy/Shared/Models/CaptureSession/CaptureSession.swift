import Foundation

struct CaptureSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var flowCount: Int
    var incompleteReason: String? = nil

    var isActive: Bool { endedAt == nil }
}
