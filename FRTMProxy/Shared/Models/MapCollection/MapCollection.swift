import Foundation

struct MapCollection: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var isEnabled: Bool
    var enabledAt: Date?
    var rules: [MapRule]
    var origin: MapCollectionOrigin?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        isEnabled: Bool = false,
        enabledAt: Date? = nil,
        rules: [MapRule] = [],
        origin: MapCollectionOrigin? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.enabledAt = enabledAt
        self.rules = rules
        self.origin = origin
    }
}
