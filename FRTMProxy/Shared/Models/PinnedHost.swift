import Foundation

struct PinnedHost: Identifiable, Codable, Equatable {
    var host: String
    var isActive: Bool
    var pinnedAt: Date

    var id: String { host }

    init(host: String, isActive: Bool = false, pinnedAt: Date = Date()) {
        self.host = PinnedHost.normalized(host)
        self.isActive = isActive
        self.pinnedAt = pinnedAt
    }

    static func normalized(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
