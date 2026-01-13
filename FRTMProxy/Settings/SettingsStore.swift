import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    @Published var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: themeKey) }
    }

    @Published var defaultPort: Int {
        didSet { defaults.set(defaultPort, forKey: portKey) }
    }

    @Published var autoStartProxy: Bool {
        didSet { defaults.set(autoStartProxy, forKey: autoStartKey) }
    }

    @Published var autoClearOnStart: Bool {
        didSet { defaults.set(autoClearOnStart, forKey: autoClearKey) }
    }

    @Published var pinnedHosts: [PinnedHost] {
        didSet { persistPinnedHosts() }
    }

    @Published var restrictInterceptionToActivePinnedHosts: Bool {
        didSet { defaults.set(restrictInterceptionToActivePinnedHosts, forKey: restrictInterceptionKey) }
    }

    @Published var selectedTrafficProfileID: String {
        didSet { defaults.set(selectedTrafficProfileID, forKey: trafficProfileKey) }
    }

    private let defaults = UserDefaults.standard
    private let themeKey = "settings.theme"
    private let portKey = "settings.defaultPort"
    private let autoStartKey = "settings.autoStart"
    private let autoClearKey = "settings.autoClear"
    private let pinnedHostsKey = "settings.pinnedHosts"
    private let restrictInterceptionKey = "settings.restrictInterceptionToActivePinnedHosts"
    private let trafficProfileKey = "settings.trafficProfile"

    var activeTheme: AppTheme {
        ThemeLibrary.theme(with: selectedThemeID)
    }

    var activeTrafficProfile: TrafficProfile {
        TrafficProfileLibrary.profile(with: selectedTrafficProfileID)
    }

    init() {
        let storedThemeID = defaults.string(forKey: themeKey)
        self.selectedThemeID = ThemeLibrary.theme(with: storedThemeID).id

        let storedPort = defaults.integer(forKey: portKey)
        self.defaultPort = (storedPort >= 1024 && storedPort <= 65535) ? storedPort : 8080
        self.autoStartProxy = defaults.bool(forKey: autoStartKey)
        self.autoClearOnStart = defaults.bool(forKey: autoClearKey)
        self.pinnedHosts = SettingsStore.loadPinnedHosts(from: defaults, key: pinnedHostsKey)
        self.restrictInterceptionToActivePinnedHosts = defaults.bool(forKey: restrictInterceptionKey)
        let storedProfileID = defaults.string(forKey: trafficProfileKey)
        self.selectedTrafficProfileID = TrafficProfileLibrary.profile(with: storedProfileID).id
    }

    func pinHost(_ rawHost: String) {
        let normalized = PinnedHost.normalized(rawHost)
        guard !normalized.isEmpty else { return }

        if pinnedHosts.contains(where: { $0.host == normalized }) {
            return
        }

        pinnedHosts.insert(PinnedHost(host: normalized), at: 0)
    }

    func unpinHost(_ rawHost: String) {
        let normalized = PinnedHost.normalized(rawHost)
        guard !normalized.isEmpty else { return }

        pinnedHosts.removeAll { $0.host == normalized }
    }

    func togglePinnedHostSelection(_ rawHost: String) {
        setPinnedHost(rawHost, active: nil)
    }

    func setPinnedHost(_ rawHost: String, active: Bool?) {
        let normalized = PinnedHost.normalized(rawHost)
        guard !normalized.isEmpty else { return }

        guard let index = pinnedHosts.firstIndex(where: { $0.host == normalized }) else { return }
        var updated = pinnedHosts
        if let active {
            updated[index].isActive = active
        } else {
            updated[index].isActive.toggle()
        }
        pinnedHosts = updated
    }

    func clearPinnedHostSelections() {
        guard pinnedHosts.contains(where: { $0.isActive }) else { return }
        var updated = pinnedHosts
        updated.indices.forEach { updated[$0].isActive = false }
        pinnedHosts = updated
    }

    private func persistPinnedHosts() {
        guard let data = try? JSONEncoder().encode(pinnedHosts) else { return }
        defaults.set(data, forKey: pinnedHostsKey)
    }

    private static func loadPinnedHosts(from defaults: UserDefaults, key: String) -> [PinnedHost] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PinnedHost].self, from: data) else {
            return []
        }
        return decoded
    }
}
