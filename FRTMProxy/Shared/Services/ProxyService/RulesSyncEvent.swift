import Foundation

struct RulesSyncEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case acknowledged = "rules_ack"
        case failed = "rules_error"
    }

    let event: Kind
    let revision: Int
    let count: Int?
    let message: String?
}
