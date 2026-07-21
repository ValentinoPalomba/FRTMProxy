import Foundation

struct TrafficRule: Codable, Hashable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    let id: UUID
    var name: String
    var isEnabled: Bool
    var priority: Int
    var matcher: TrafficRuleMatcher
    /// Actions execute in array order. IDs remain stable when actions are reordered.
    var actions: [TrafficRuleAction]

    init(
        schemaVersion: Int = TrafficRule.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        matcher: TrafficRuleMatcher,
        actions: [TrafficRuleAction]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.matcher = matcher
        self.actions = actions
    }
}
