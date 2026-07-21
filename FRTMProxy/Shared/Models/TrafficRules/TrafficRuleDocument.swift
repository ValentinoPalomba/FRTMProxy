import Foundation

struct TrafficRuleDocument: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var rules: [TrafficRule]

    init(schemaVersion: Int = currentSchemaVersion, rules: [TrafficRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }
}
