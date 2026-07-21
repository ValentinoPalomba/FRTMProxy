import Combine
import Foundation
import AppKit
import Network

final class ProxyViewModel: ObservableObject {
    @Published var flows: [MitmFlow] = []
    @Published var selectedFlowID: String?
    @Published var logText: String = ""
    @Published var isRunning: Bool = false
    @Published var rules: [String: MapRule] = [:]
    @Published var collections: [MapCollection] = []
    @Published var gitCollectionSources: [GitCollectionSource] = []
    @Published var recordingCollectionName: String?
    @Published var recordingRulesPreview: [MapRule] = []
    @Published var activePort: Int
    @Published var breakpointRules: [String: FlowBreakpointRule] = [:]
    @Published var activeBreakpointHit: FlowBreakpointHit?
    @Published var activeTrafficProfile: TrafficProfile = TrafficProfileLibrary.disabled
    @Published var captureSessions: [CaptureSession] = []
    @Published var activeCaptureSessionID: UUID?
    @Published var trafficRuleDocument = TrafficRuleDocument(rules: [])

    @Published var scripts: [ScriptRule] = []

    let service: ProxyServiceProtocol
    let ruleStore: MapRuleStoreProtocol
    let collectionStore: MapCollectionStoreProtocol
    let breakpointStore: BreakpointStoreProtocol
    let scriptStore: ScriptStore
    let sessionStore: (any SessionStoreProtocol)?
    let trafficRuleStore: TrafficRuleStoreProtocol
    let collectionRecorder = CollectionRecorder()
    var cancellables: Set<AnyCancellable> = []
    var settingsCancellables: Set<AnyCancellable> = []
    var defaultPort: Int
    var autoClearOnStart = false
    var overrideMacOSProxy = false
    var appliedRules: [String: MapRule] = [:]
    var recordedFlowIDs: Set<String> = []
    var appliedBreakpointRules: [String: FlowBreakpointRule] = [:]
    var breakpointQueue: [FlowBreakpointHit] = []
    var restrictInterceptionToHosts = false
    var interceptionHosts: [String] = []
    var lastInterceptionConfigHash: Int?
    let clientAppResolver = ClientAppResolver()
    var clientAppByConnectionKey: [String: FlowClientApp] = [:]
    var resolvingConnectionKeys: Set<String> = []
    var alertsEnabled = false
    var alertRules: [AlertRule] = []
    var alertFiltersByRuleID: [UUID: FlowFilter] = [:]
    var alertRuleQueryByID: [UUID: String] = [:]
    var triggeredAlertKeys: Set<String> = []
    var seenAlertFlowIDs: Set<String> = []
    var processedScriptFlowIDs: Set<String> = []
    var networkPathMonitor: NWPathMonitor?
    let networkPathMonitorQueue = DispatchQueue(label: "com.frtmproxy.network-path-monitor", qos: .utility)
    var wakeObserver: NSObjectProtocol?
    var lastProxyReassertAt: Date = .distantPast
    var onToast: ((String, ToastStyle) -> Void)?

    init(
        service: ProxyServiceProtocol = MitmproxyService(config: MitmproxyConfig()),
        ruleStore: MapRuleStoreProtocol = MapRuleStore(),
        collectionStore: MapCollectionStoreProtocol = MapCollectionStore(),
        breakpointStore: BreakpointStoreProtocol = FlowBreakpointStore(),
        scriptStore: ScriptStore = ScriptStore(),
        sessionStore: (any SessionStoreProtocol)? = nil,
        trafficRuleStore: TrafficRuleStoreProtocol = TrafficRuleStore(),
        defaultPort: Int = 8080
    ) {
        self.service = service
        self.ruleStore = ruleStore
        self.collectionStore = collectionStore
        self.breakpointStore = breakpointStore
        self.scriptStore = scriptStore
        self.sessionStore = sessionStore ?? Self.makeDefaultSessionStore()
        self.trafficRuleStore = trafficRuleStore
        self.defaultPort = defaultPort
        self.activePort = defaultPort
        bind()
        loadPersistedRules()
        loadPersistedCollections()
        loadPersistedGitSources()
        loadPersistedBreakpoints()
        loadPersistedScripts()
        loadUnifiedTrafficRules()
        syncAppliedRules()
        syncBreakpointRules()
        loadCaptureSessions()
    }

    private static func makeDefaultSessionStore() -> (any SessionStoreProtocol)? {
        let databaseURL = URL.applicationSupportDirectory
            .appending(path: "FRTMProxy", directoryHint: .isDirectory)
            .appending(path: "Sessions", directoryHint: .isDirectory)
            .appending(path: "sessions.sqlite")
        return try? SQLiteSessionStore(databaseURL: databaseURL)
    }

    deinit {
        networkPathMonitor?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    var selectedFlow: MitmFlow? {
        flows.first(where: { $0.id == selectedFlowID })
    }

    var orderedBreakpointRules: [FlowBreakpointRule] {
        breakpointRules.values.sorted(by: { $0.key < $1.key })
    }

    @MainActor
    func startProxy(port: Int? = nil) async {
        if autoClearOnStart {
            clear()
        }
        let selectedPort = port ?? defaultPort
        do {
            await ensureCaptureSession()
            try await service.startProxy(
                port: selectedPort,
                restrictToHosts: restrictInterceptionToHosts,
                hosts: interceptionHosts
            )
            activePort = selectedPort
            updateMacOSProxyOverridePort()
            reapplyStoredRules()
            reapplyBreakpointRules()
        } catch {
            logText.append("\n\(error.localizedDescription)")
            onToast?("Failed to start proxy: \(error.localizedDescription)", .error)
        }
    }

    func stopProxy() {
        service.stopProxy()
        closeActiveCaptureSession()
    }

    func clear() {
        flows.removeAll()
        selectedFlowID = nil
        clientAppByConnectionKey.removeAll()
        resolvingConnectionKeys.removeAll()
        processedScriptFlowIDs.removeAll()
        service.clearFlows()
    }

    func selectTrafficProfile(_ profile: TrafficProfile) {
        setTrafficProfile(profile)
    }

    func appendLog(_ text: String) {
        // keep last ~10k chars to avoid UI re-render thrashing
        let newText = logText + text
        if newText.count > 10_000 {
            let suffixStart = newText.index(newText.endIndex, offsetBy: -8_000)
            logText = String(newText[suffixStart...])
        } else {
            logText = newText
        }

        if ProcessInfo.processInfo.environment["FRTMPROXY_STDOUT_LOGS"] == "1" {
            print(text, terminator: "")
        }
    }
}
