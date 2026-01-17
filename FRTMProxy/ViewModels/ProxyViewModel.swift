import Combine
import Foundation
import CoreData

final class ProxyViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    @Published var flows: [CDFlow] = []
    @Published var selectedFlowID: String?
    @Published var logText: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published var rules: [String: MapRule] = [:]
    @Published var collections: [MapCollection] = []
    @Published private(set) var recordingCollectionName: String?
    @Published private(set) var recordingRulesPreview: [MapRule] = []
    @Published private(set) var activePort: Int
    @Published var breakpointRules: [String: FlowBreakpointRule] = [:]
    @Published private(set) var activeBreakpointHit: FlowBreakpointHit?
    @Published private(set) var activeTrafficProfile: TrafficProfile = TrafficProfileLibrary.disabled
    
    private let service: ProxyServiceProtocol
    private let ruleStore: MapRuleStoreProtocol
    private let collectionStore: MapCollectionStoreProtocol
    private let breakpointStore: BreakpointStoreProtocol
    private let collectionRecorder = CollectionRecorder()
    private var cancellables: Set<AnyCancellable> = []
    private var settingsCancellables: Set<AnyCancellable> = []
    private var defaultPort: Int
    private var autoClearOnStart = false
    private var appliedRules: [String: MapRule] = [:]
    private var recordedFlowIDs: Set<String> = []
    private var appliedBreakpointRules: [String: FlowBreakpointRule] = [:]
    private var breakpointQueue: [FlowBreakpointHit] = []
    private var restrictInterceptionToHosts = false
    private var interceptionHosts: [String] = []
    private var lastInterceptionConfigHash: Int?
    private let fetchedResultsController: NSFetchedResultsController<CDFlow>
    private let moc: NSManagedObjectContext
    
    init(
        service: ProxyServiceProtocol = MitmproxyService(config: MitmproxyConfig()),
        ruleStore: MapRuleStoreProtocol = MapRuleStore(),
        collectionStore: MapCollectionStoreProtocol = MapCollectionStore(),
        breakpointStore: BreakpointStoreProtocol = FlowBreakpointStore(),
        defaultPort: Int = 8080,
        moc: NSManagedObjectContext = StorageService.shared.viewContext
    ) {
        self.service = service
        self.ruleStore = ruleStore
        self.collectionStore = collectionStore
        self.breakpointStore = breakpointStore
        self.defaultPort = defaultPort
        self.activePort = defaultPort
        self.moc = moc

        let fetchRequest: NSFetchRequest<CDFlow> = CDFlow.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDFlow.timestamp, ascending: false)]
        self.fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: moc,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        super.init()

        self.fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
            self.flows = fetchedResultsController.fetchedObjects ?? []
        } catch {
            logText.append("\n[DB] Failed to fetch flows: \(error.localizedDescription)")
        }

        bind()
        loadPersistedRules()
        loadPersistedCollections()
        loadPersistedBreakpoints()
        syncAppliedRules()
        syncBreakpointRules()
    }
    
    var selectedFlow: CDFlow? {
        guard let selectedFlowID = selectedFlowID else { return nil }
        return flows.first(where: { $0.id == selectedFlowID })
    }

    var orderedBreakpointRules: [FlowBreakpointRule] {
        breakpointRules.values.sorted(by: { $0.key < $1.key })
    }
    
    func startProxy(port: Int? = nil) {
        if autoClearOnStart {
            clear()
        }
        let selectedPort = port ?? defaultPort
        do {
            try service.startProxy(
                port: selectedPort,
                restrictToHosts: restrictInterceptionToHosts,
                hosts: interceptionHosts
            )
            activePort = selectedPort
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
        service.clearFlows()
    }

    func selectTrafficProfile(_ profile: TrafficProfile) {
        setTrafficProfile(profile)
    }
    
    func mapResponse(body: String, status: Int? = nil, headers: [String: String]? = nil) {
        guard let flow = selectedFlow,
              let ruleKey = mapKey(for: flow) else { return }
        let rule = MapRule(
            key: ruleKey.key,
            host: ruleKey.host,
            path: ruleKey.path,
            scheme: ruleKey.scheme,
            body: body,
            status: status ?? Int(flow.responseStatus),
            headers: headers ?? decodeResponseHeaders(from: flow)
        )
        rules[rule.key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
    }

    @discardableResult
    func createRule(host: String, path: String) -> MapRule? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        if trimmedPath.isEmpty {
            trimmedPath = "/"
        }
        if !trimmedPath.hasPrefix("/") {
            trimmedPath = "/" + trimmedPath
        }

        let key = trimmedHost + trimmedPath
        guard rules[key] == nil else { return rules[key] }

        let rule = MapRule(
            key: key,
            host: trimmedHost,
            path: trimmedPath,
            scheme: "https",
            body: "",
            status: 200,
            headers: [:],
            isEnabled: true
        )
        rules[key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
        return rule
    }

    func setRule(_ key: String, enabled: Bool) {
        guard var rule = rules[key] else { return }
        rule.isEnabled = enabled
        rules[key] = rule
        persistRules()
        syncAppliedRules()
    }

    func retryFlow(with payload: MapEditorRetryPayload) {
        service.retryFlow(
            flowID: payload.flowID,
            method: payload.method,
            url: payload.url,
            body: payload.body,
            headers: payload.headers
        )
    }
    
    func applyMapLocal(
        requestBody: String?,
        requestHeaders: [String: String],
        responseBody: String,
        status: Int,
        headers: [String: String]
    ) {
        if let requestBody, let flowID = selectedFlow?.id {
            service.mockRequest(for: flowID, body: requestBody, headers: requestHeaders)
        }
        if let flowID = selectedFlow?.id {
            service.mockResponse(for: flowID, body: responseBody, status: status, headers: headers)
        }
    }
    
    // MARK: - Breakpoints

    func isBreakpointEnabled(for flow: CDFlow, phase: FlowBreakpointPhase) -> Bool {
        guard let info = mapKey(for: flow),
              let rule = breakpointRules[info.key], rule.isEnabled else { return false }
        switch phase {
        case .request:
            return rule.interceptRequest
        case .response:
            return rule.interceptResponse
        }
    }

    func setBreakpoint(for flow: CDFlow, phase: FlowBreakpointPhase, enabled: Bool) {
        guard let info = mapKey(for: flow) else { return }
        var rule = breakpointRules[info.key] ?? FlowBreakpointRule(
            key: info.key,
            host: info.host,
            path: info.path,
            scheme: info.scheme,
            interceptRequest: false,
            interceptResponse: false,
            isEnabled: true
        )
        switch phase {
        case .request:
            rule.interceptRequest = enabled
        case .response:
            rule.interceptResponse = enabled
        }
        if rule.interceptRequest || rule.interceptResponse {
            rule.isEnabled = true
        } else {
            rule.isEnabled = false
        }

        saveBreakpointRule(rule)
    }

    func removeBreakpoint(for flow: CDFlow) {
        guard let info = mapKey(for: flow) else { return }
        deleteBreakpoint(key: info.key)
    }

    func createBreakpoint(host: String, path: String, interceptRequest: Bool, interceptResponse: Bool) -> FlowBreakpointRule? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else { return nil }
        if trimmedPath.isEmpty {
            trimmedPath = "/"
        }
        if !trimmedPath.hasPrefix("/") {
            trimmedPath = "/" + trimmedPath
        }
        guard interceptRequest || interceptResponse else { return nil }

        let key = trimmedHost + trimmedPath
        let rule = FlowBreakpointRule(
            key: key,
            host: trimmedHost,
            path: trimmedPath,
            scheme: "https",
            interceptRequest: interceptRequest,
            interceptResponse: interceptResponse,
            isEnabled: true
        )
        saveBreakpointRule(rule)
        return rule
    }

    func setBreakpointEnabled(_ key: String, enabled: Bool) {
        guard var rule = breakpointRules[key] else { return }
        if enabled && !rule.interceptRequest && !rule.interceptResponse {
            rule.interceptRequest = true
        }
        rule.isEnabled = enabled && (rule.interceptRequest || rule.interceptResponse)
        saveBreakpointRule(rule)
    }

    func updateBreakpointPhases(key: String, request: Bool, response: Bool) {
        guard var rule = breakpointRules[key] else { return }
        rule.interceptRequest = request
        rule.interceptResponse = response
        rule.isEnabled = rule.isEnabled && (request || response)
        if !request && !response {
            rule.isEnabled = false
        }
        saveBreakpointRule(rule)
    }

    func deleteBreakpoint(key: String) {
        breakpointRules.removeValue(forKey: key)
        persistBreakpoints()
        syncBreakpointRules()
    }

    func flow(withID id: String) -> CDFlow? {
        flows.first(where: { $0.id == id })
    }

    func continueActiveBreakpoint(using editor: MapEditorViewModel) {
        guard let hit = activeBreakpointHit,
              let flow = flow(withID: hit.flowID) else { return }

        switch hit.phase {
        case .request:
            guard let retryPayload = editor.retryPayload() else { return }
            let requestPayload = BreakpointRequestPayload(
                method: retryPayload.method,
                url: retryPayload.url,
                headers: retryPayload.headers,
                body: retryPayload.body
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .request,
                requestPayload: requestPayload,
                responsePayload: nil
            )
        case .response:
            let defaultStatus = Int(flow.responseStatus)
            guard let payload = editor.payload(defaultStatus: defaultStatus) else { return }
            let responsePayload = BreakpointResponsePayload(
                status: payload.responseStatus,
                headers: payload.responseHeaders,
                body: payload.responseBody
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .response,
                requestPayload: nil,
                responsePayload: responsePayload
            )
        }

        consumeActiveBreakpoint()
    }

    func skipActiveBreakpoint() {
        guard let hit = activeBreakpointHit,
              let flow = flow(withID: hit.flowID) else { return }
        switch hit.phase {
        case .request:
            let payload = BreakpointRequestPayload(
                method: flow.requestMethod ?? "",
                url: flow.requestURL ?? "",
                headers: decodeRequestHeaders(from: flow),
                body: flow.requestBody
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .request,
                requestPayload: payload,
                responsePayload: nil
            )
        case .response:
            let payload = BreakpointResponsePayload(
                status: Int(flow.responseStatus),
                headers: decodeResponseHeaders(from: flow),
                body: flow.responseBody ?? ""
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .response,
                requestPayload: nil,
                responsePayload: payload
            )
        }
        consumeActiveBreakpoint()
    }
    
    func bind(settings: SettingsStore) {
        settingsCancellables.removeAll()

        settings.$defaultPort
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPort in
                self?.defaultPort = newPort
            }
            .store(in: &settingsCancellables)

        settings.$autoClearOnStart
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flag in
                self?.autoClearOnStart = flag
            }
            .store(in: &settingsCancellables)

        settings.$autoStartProxy
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] autoStart in
                guard let self else { return }
                if autoStart && !self.isRunning {
                    self.startProxy()
                }
            }
            .store(in: &settingsCancellables)

        settings.$restrictInterceptionToActivePinnedHosts
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flag in
                self?.restrictInterceptionToHosts = flag
                self?.handleInterceptionConfigChanged()
            }
            .store(in: &settingsCancellables)

        settings.$pinnedHosts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinnedHosts in
                self?.interceptionHosts = pinnedHosts.filter(\.isActive).map(\.host)
                self?.handleInterceptionConfigChanged()
            }
            .store(in: &settingsCancellables)

        settings.$selectedTrafficProfileID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profileID in
                guard let self else { return }
                let profile = TrafficProfileLibrary.profile(with: profileID)
                self.setTrafficProfile(profile)
            }
            .store(in: &settingsCancellables)

        defaultPort = settings.defaultPort
        autoClearOnStart = settings.autoClearOnStart
        restrictInterceptionToHosts = settings.restrictInterceptionToActivePinnedHosts
        interceptionHosts = settings.pinnedHosts.filter(\.isActive).map(\.host)
        setTrafficProfile(settings.activeTrafficProfile, force: true)

        if settings.autoStartProxy && !isRunning {
            startProxy()
        }
    }

    private func handleInterceptionConfigChanged() {
        let configHash = restrictInterceptionToHosts.hashValue ^ interceptionHosts.joined(separator: ",").hashValue
        guard configHash != lastInterceptionConfigHash else { return }
        lastInterceptionConfigHash = configHash
        guard isRunning else { return }
        logText.append("\n[PROXY] Domain filter changed. Restart the proxy to apply.")
    }

    func updateRule(
        key: String,
        body: String,
        status: Int,
        headers: [String: String],
        isEnabled: Bool
    ) {
        guard var rule = rules[key] else { return }
        rule.body = body
        rule.status = status
        rule.headers = headers
        rule.isEnabled = isEnabled
        rules[key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
    }

    func deleteRule(key: String) {
        rules.removeValue(forKey: key)
        persistRules()
        syncAppliedRules()
    }

    // MARK: - Collections

    var isRecordingCollection: Bool {
        recordingCollectionName != nil
    }

    func startCollectionRecording(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collectionRecorder.isRecording else { return }
        collectionRecorder.start(name: trimmed)
        recordingCollectionName = trimmed
        recordingRulesPreview = []
        recordedFlowIDs = Set(flows.map { $0.id })
    }

    func stopCollectionRecording(save: Bool) {
        guard collectionRecorder.isRecording else { return }
        defer {
            recordingCollectionName = nil
            recordingRulesPreview = []
            recordedFlowIDs = []
        }
        if save, let collection = collectionRecorder.stopAndCreateCollection() {
            collections.append(collection)
            persistCollections()
            syncAppliedRules()
        } else {
            collectionRecorder.discard()
        }
    }

    func toggleCollection(_ id: UUID, enabled: Bool) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].isEnabled = enabled
        collections[index].enabledAt = enabled ? Date() : nil
        persistCollections()
        syncAppliedRules()
    }

    func renameCollection(_ id: UUID, newName: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
        persistCollections()
    }

    func deleteCollection(_ id: UUID) {
        let originalCount = collections.count
        collections.removeAll { $0.id == id }
        if originalCount != collections.count {
            persistCollections()
            syncAppliedRules()
        }
    }

    func updateRule(inCollection id: UUID, rule: MapRule) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        if let ruleIndex = collections[collectionIndex].rules.firstIndex(where: { $0.key == rule.key }) {
            collections[collectionIndex].rules[ruleIndex] = rule
        } else {
            collections[collectionIndex].rules.append(rule)
        }
        persistCollections()
        syncAppliedRules()
    }

    func deleteRule(inCollection id: UUID, ruleKey: String) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[collectionIndex].rules.removeAll { $0.key == ruleKey }
        persistCollections()
        syncAppliedRules()
    }

    func updateRecordingRule(_ rule: MapRule) {
        guard collectionRecorder.isRecording else { return }
        collectionRecorder.record(rule: rule)
        recordingRulesPreview = collectionRecorder.currentRules()
    }

    func exportCollection(_ id: UUID, to destinationURL: URL) throws {
        guard let collection = collections.first(where: { $0.id == id }) else { return }
        try collectionStore.export(collection: collection, to: destinationURL)
    }

    func importCollection(from url: URL) throws {
        let collection = try collectionStore.importCollection(at: url)
        collections.append(collection)
        persistCollections()
        syncAppliedRules()
    }

    private func mapKey(for flow: CDFlow) -> (key: String, host: String, path: String, scheme: String?)? {
        guard let urlString = flow.requestURL,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        let path = url.path
        return (key: host + path, host: host, path: path.isEmpty ? "/" : path, scheme: url.scheme)
    }

    private func decodeRequestHeaders(from flow: CDFlow) -> [String: String] {
        guard let data = flow.requestHeaders else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func decodeResponseHeaders(from flow: CDFlow) -> [String: String] {
        guard let data = flow.responseHeaders else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    
    private func bind() {
        service.flowsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Handled by NSFetchedResultsControllerDelegate
            }
            .store(in: &cancellables)

        service.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.isRunning = running
                if running {
                    self.service.applyTrafficProfile(self.activeTrafficProfile)
                }
            }
            .store(in: &cancellables)
        
        service.onLog = { [weak self] text in
            DispatchQueue.main.async {
                self?.appendLog(text)
            }
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let newFlows = fetchedResultsController.fetchedObjects ?? []
        self.flows = newFlows

        if selectedFlowID == nil, let firstID = newFlows.first?.id {
            selectedFlowID = firstID
        }

        captureRecordingRules(from: newFlows)
        enqueueBreakpointHits(from: newFlows)
    }

    private func loadPersistedRules() {
        let stored = ruleStore.loadRules()
        stored.forEach { rule in
            rules[rule.key] = rule
        }
    }

    private func loadPersistedCollections() {
        collections = collectionStore.loadCollections()
    }

    private func loadPersistedBreakpoints() {
        let stored = breakpointStore.loadBreakpoints()
        stored.forEach { rule in
            breakpointRules[rule.key] = rule
        }
    }

    private func persistRules() {
        let array = rules.values.sorted(by: { $0.key < $1.key })
        ruleStore.save(rules: array)
    }

    private func persistCollections() {
        collectionStore.save(collections: collections)
    }

    private func persistBreakpoints() {
        let array = breakpointRules.values.sorted(by: { $0.key < $1.key })
        breakpointStore.save(breakpoints: array)
    }

    private func setTrafficProfile(_ profile: TrafficProfile, force: Bool = false) {
        if !force && profile == activeTrafficProfile {
            return
        }
        activeTrafficProfile = profile
        if isRunning {
            service.applyTrafficProfile(profile)
        }
    }

    private func saveBreakpointRule(_ rule: FlowBreakpointRule) {
        breakpointRules[rule.key] = rule
        persistBreakpoints()
        syncBreakpointRules()
    }

    private func reapplyStoredRules() {
        appliedRules.removeAll()
        syncAppliedRules()
    }

    private func reapplyBreakpointRules() {
        appliedBreakpointRules.removeAll()
        syncBreakpointRules()
    }

    private func record(rule: MapRule) {
        guard collectionRecorder.isRecording else { return }
        collectionRecorder.record(rule: rule)
        recordingRulesPreview = collectionRecorder.currentRules()
    }

    private func captureRecordingRules(from flows: [CDFlow]) {
        guard collectionRecorder.isRecording else { return }
        for flow in flows {
            guard !recordedFlowIDs.contains(flow.id),
                  let info = mapKey(for: flow) else { continue }

            let rule = MapRule(
                key: info.key,
                host: info.host,
                path: info.path,
                scheme: info.scheme,
                body: flow.responseBody ?? "",
                status: Int(flow.responseStatus),
                headers: decodeResponseHeaders(from: flow),
                isEnabled: true
            )
            record(rule: rule)
            recordedFlowIDs.insert(flow.id)
        }
    }

    private func enqueueBreakpointHits(from flows: [CDFlow]) {
        var waitingIDs: Set<String> = []

        for flow in flows {
            guard let state = flow.breakpointState,
                  state == FlowBreakpointState.waiting.rawValue,
                  let phaseRaw = flow.breakpointPhase,
                  let phase = FlowBreakpointPhase(rawValue: phaseRaw),
                  let key = flow.breakpointKey else { continue }

            let hit = FlowBreakpointHit(
                flowID: flow.id,
                phase: phase,
                key: key,
                timestamp: flow.timestamp
            )
            waitingIDs.insert(hit.id)

            if !breakpointQueue.contains(where: { $0.id == hit.id }) {
                breakpointQueue.append(hit)
            }
        }

        breakpointQueue.removeAll { !waitingIDs.contains($0.id) }

        if let active = activeBreakpointHit, !waitingIDs.contains(active.id) {
            activeBreakpointHit = nil
        }

        if activeBreakpointHit == nil {
            activeBreakpointHit = breakpointQueue.first
        }
    }

    private func consumeActiveBreakpoint() {
        guard let hit = activeBreakpointHit else { return }
        breakpointQueue.removeAll { $0.id == hit.id }
        activeBreakpointHit = breakpointQueue.first
    }

    private func appendLog(_ text: String) {
        // keep last ~10k chars to avoid UI re-render thrashing
        let newText = logText + text
        if newText.count > 10_000 {
            let suffixStart = newText.index(newText.endIndex, offsetBy: -8_000)
            logText = String(newText[suffixStart...])
        } else {
            logText = newText
        }
    }
}
