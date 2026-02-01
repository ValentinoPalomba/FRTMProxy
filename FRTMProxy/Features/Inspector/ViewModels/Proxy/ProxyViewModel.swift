import Combine
import Foundation

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

    let service: ProxyServiceProtocol
    let ruleStore: MapRuleStoreProtocol
    let collectionStore: MapCollectionStoreProtocol
    let breakpointStore: BreakpointStoreProtocol
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

    init(
        service: ProxyServiceProtocol = MitmproxyService(config: MitmproxyConfig()),
        ruleStore: MapRuleStoreProtocol = MapRuleStore(),
        collectionStore: MapCollectionStoreProtocol = MapCollectionStore(),
        breakpointStore: BreakpointStoreProtocol = FlowBreakpointStore(),
        defaultPort: Int = 8080
    ) {
        self.service = service
        self.ruleStore = ruleStore
        self.collectionStore = collectionStore
        self.breakpointStore = breakpointStore
        self.defaultPort = defaultPort
        self.activePort = defaultPort
        bind()
        loadPersistedRules()
        loadPersistedCollections()
        loadPersistedGitSources()
        loadPersistedBreakpoints()
        syncAppliedRules()
        syncBreakpointRules()
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
        }
    }

    func stopProxy() {
        service.stopProxy()
    }

    func clear() {
        flows.removeAll()
        selectedFlowID = nil
        clientAppByConnectionKey.removeAll()
        resolvingConnectionKeys.removeAll()
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

        print(text)
    }
}
