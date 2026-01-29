import Foundation

struct FlowClientApp: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var displayName: String
    var bundleIdentifier: String?
    var bundleURL: String?
    var pid: Int?

    init(
        id: String,
        displayName: String,
        bundleIdentifier: String? = nil,
        bundleURL: String? = nil,
        pid: Int? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleURL = bundleURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pid = pid
    }

    static func normalizedID(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
