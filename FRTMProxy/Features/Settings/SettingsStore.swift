import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    @Published var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: themeKey) }
    }

    @Published var interfaceScaleID: String {
        didSet {
            defaults.set(interfaceScaleID, forKey: interfaceScaleKey)
            DesignSystem.Metrics.applyInterfaceScale(activeInterfaceScale)
        }
    }

    @Published var gitAuthorName: String {
        didSet { defaults.set(gitAuthorName, forKey: gitAuthorNameKey) }
    }

    @Published var gitAuthorEmail: String {
        didSet { defaults.set(gitAuthorEmail, forKey: gitAuthorEmailKey) }
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

    @Published var overrideMacOSProxy: Bool {
        didSet { defaults.set(overrideMacOSProxy, forKey: macOSProxyOverrideKey) }
    }

    @Published var pinnedHosts: [PinnedHost] {
        didSet { persistPinnedHosts() }
    }

    @Published var pinnedApps: [PinnedApp] {
        didSet { persistPinnedApps() }
    }

    @Published var restrictInterceptionToActivePinnedHosts: Bool {
        didSet { defaults.set(restrictInterceptionToActivePinnedHosts, forKey: restrictInterceptionKey) }
    }

    @Published var selectedTrafficProfileID: String {
        didSet { defaults.set(selectedTrafficProfileID, forKey: trafficProfileKey) }
    }

    @Published var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: alertsEnabledKey) }
    }

    @Published var alertRules: [AlertRule] {
        didSet { persistAlertRules() }
    }


    private let defaults = UserDefaults.standard
    private let themeKey = "settings.theme"
    private let interfaceScaleKey = DesignSystem.Metrics.interfaceScaleStorageKey
    private let gitAuthorNameKey = "settings.gitAuthorName"
    private let gitAuthorEmailKey = "settings.gitAuthorEmail"
    private let portKey = "settings.defaultPort"
    private let autoStartKey = "settings.autoStart"
    private let autoClearKey = "settings.autoClear"
    private let macOSProxyOverrideKey = "settings.macosProxyOverride"
    private let pinnedHostsKey = "settings.pinnedHosts"
    private let pinnedAppsKey = "settings.pinnedApps"
    private let restrictInterceptionKey = "settings.restrictInterceptionToActivePinnedHosts"
    private let trafficProfileKey = "settings.trafficProfile"
    private let alertsEnabledKey = "settings.alertsEnabled"
    private let alertRulesKey = "settings.alertRules"

    var activeTheme: AppTheme {
        ThemeLibrary.theme(with: selectedThemeID)
    }

    var activeInterfaceScale: DesignSystem.InterfaceScale {
        DesignSystem.InterfaceScale.option(with: interfaceScaleID)
    }

    var activeTrafficProfile: TrafficProfile {
        TrafficProfileLibrary.profile(with: selectedTrafficProfileID)
    }

    init() {
        let storedThemeID = defaults.string(forKey: themeKey)
        self.selectedThemeID = ThemeLibrary.theme(with: storedThemeID).id
        let storedInterfaceScaleID = defaults.string(forKey: interfaceScaleKey)
        self.interfaceScaleID = DesignSystem.InterfaceScale.option(with: storedInterfaceScaleID).id
        self.gitAuthorName = defaults.string(forKey: gitAuthorNameKey) ?? ""
        self.gitAuthorEmail = defaults.string(forKey: gitAuthorEmailKey) ?? ""

        let storedPort = defaults.integer(forKey: portKey)
        self.defaultPort = (storedPort >= 1024 && storedPort <= 65535) ? storedPort : 8080
        self.autoStartProxy = defaults.bool(forKey: autoStartKey)
        self.autoClearOnStart = defaults.bool(forKey: autoClearKey)
        self.overrideMacOSProxy = defaults.bool(forKey: macOSProxyOverrideKey)
        self.pinnedHosts = SettingsStore.loadPinnedHosts(from: defaults, key: pinnedHostsKey)
        self.pinnedApps = SettingsStore.loadPinnedApps(from: defaults, key: pinnedAppsKey)
        self.restrictInterceptionToActivePinnedHosts = defaults.bool(forKey: restrictInterceptionKey)
        let storedProfileID = defaults.string(forKey: trafficProfileKey)
        self.selectedTrafficProfileID = TrafficProfileLibrary.profile(with: storedProfileID).id

        self.alertsEnabled = defaults.bool(forKey: alertsEnabledKey)
        self.alertRules = SettingsStore.loadAlertRules(from: defaults, key: alertRulesKey)

        DesignSystem.Metrics.applyInterfaceScale(activeInterfaceScale)
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

    func pinApp(_ app: FlowClientApp) {
        let normalizedID = FlowClientApp.normalizedID(app.id)
        guard !normalizedID.isEmpty else { return }

        if pinnedApps.contains(where: { $0.appID == normalizedID }) {
            return
        }

        pinnedApps.insert(PinnedApp(app: app), at: 0)
    }

    func unpinApp(_ rawAppID: String) {
        let normalizedID = FlowClientApp.normalizedID(rawAppID)
        guard !normalizedID.isEmpty else { return }

        pinnedApps.removeAll { $0.appID == normalizedID }
    }

    func togglePinnedAppSelection(_ rawAppID: String) {
        setPinnedApp(rawAppID, active: nil)
    }

    func setPinnedApp(_ rawAppID: String, active: Bool?) {
        let normalizedID = FlowClientApp.normalizedID(rawAppID)
        guard !normalizedID.isEmpty else { return }

        guard let index = pinnedApps.firstIndex(where: { $0.appID == normalizedID }) else { return }
        var updated = pinnedApps
        if let active {
            updated[index].isActive = active
        } else {
            updated[index].isActive.toggle()
        }
        pinnedApps = updated
    }

    func clearPinnedAppSelections() {
        guard pinnedApps.contains(where: { $0.isActive }) else { return }
        var updated = pinnedApps
        updated.indices.forEach { updated[$0].isActive = false }
        pinnedApps = updated
    }

    func activateOnlyPinnedApp(_ rawAppID: String) {
        let normalizedID = FlowClientApp.normalizedID(rawAppID)
        guard !normalizedID.isEmpty else { return }
        guard pinnedApps.contains(where: { $0.appID == normalizedID }) else { return }

        var updated = pinnedApps
        updated.indices.forEach { index in
            updated[index].isActive = updated[index].appID == normalizedID
        }
        pinnedApps = updated
    }

    func upsertAlertRule(_ rule: AlertRule) {
        let normalized = AlertRule(
            id: rule.id,
            name: rule.name,
            query: rule.query,
            isEnabled: rule.isEnabled,
            createdAt: rule.createdAt
        )

        if let index = alertRules.firstIndex(where: { $0.id == normalized.id }) {
            alertRules[index] = normalized
        } else {
            alertRules.insert(normalized, at: 0)
        }
    }

    func deleteAlertRule(_ id: UUID) {
        alertRules.removeAll { $0.id == id }
    }

    private func persistAlertRules() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(alertRules) else { return }
        defaults.set(data, forKey: alertRulesKey)
    }

    private static func loadAlertRules(from defaults: UserDefaults, key: String) -> [AlertRule] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistPinnedHosts() {
        guard let data = try? JSONEncoder().encode(pinnedHosts) else { return }
        defaults.set(data, forKey: pinnedHostsKey)
    }

    private func persistPinnedApps() {
        guard let data = try? JSONEncoder().encode(pinnedApps) else { return }
        defaults.set(data, forKey: pinnedAppsKey)
    }

    private static func loadPinnedHosts(from defaults: UserDefaults, key: String) -> [PinnedHost] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PinnedHost].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func loadPinnedApps(from defaults: UserDefaults, key: String) -> [PinnedApp] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PinnedApp].self, from: data) else {
            return []
        }
        return decoded
    }
}
