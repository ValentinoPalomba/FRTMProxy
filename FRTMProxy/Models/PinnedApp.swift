import Foundation

struct PinnedApp: Identifiable, Codable, Equatable {
    var appID: String
    var displayName: String
    var bundleIdentifier: String?
    var bundleURL: String?
    var isActive: Bool
    var pinnedAt: Date

    var id: String { appID }

    init(appID: String, displayName: String, bundleIdentifier: String?, bundleURL: String?, isActive: Bool = false, pinnedAt: Date = Date()) {
        self.appID = FlowClientApp.normalizedID(appID)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleURL = bundleURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isActive = isActive
        self.pinnedAt = pinnedAt
    }

    init(app: FlowClientApp, isActive: Bool = false, pinnedAt: Date = Date()) {
        self.init(
            appID: app.id,
            displayName: app.displayName,
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL,
            isActive: isActive,
            pinnedAt: pinnedAt
        )
    }
}

