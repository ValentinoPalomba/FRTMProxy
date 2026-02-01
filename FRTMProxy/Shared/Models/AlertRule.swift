import Foundation

struct AlertRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var query: String
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        query: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

