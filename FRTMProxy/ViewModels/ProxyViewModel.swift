import Combine
import Foundation


final class ProxyViewModel: ObservableObject {
    @Published var flows: [MitmFlow] = []
    @Published var selectedFlowID: String?
    @Published var logText: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published var rules: [String: MapRule] = [:]
    @Published var collections: [MapCollection] = []
    @Published var gitCollectionSources: [GitCollectionSource] = []
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
    private var overrideMacOSProxy = false
    private var appliedRules: [String: MapRule] = [:]
    private var recordedFlowIDs: Set<String> = []
    private var appliedBreakpointRules: [String: FlowBreakpointRule] = [:]
    private var breakpointQueue: [FlowBreakpointHit] = []
    private var restrictInterceptionToHosts = false
    private var interceptionHosts: [String] = []
    private var lastInterceptionConfigHash: Int?
    private let clientAppResolver = ClientAppResolver()
    private var clientAppByConnectionKey: [String: FlowClientApp] = [:]
    private var resolvingConnectionKeys: Set<String> = []
    private var alertsEnabled = false
    private var alertRules: [AlertRule] = []
    private var alertFiltersByRuleID: [UUID: FlowFilter] = [:]
    private var alertRuleQueryByID: [UUID: String] = [:]
    private var triggeredAlertKeys: Set<String> = []
    private var seenAlertFlowIDs: Set<String> = []
    
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
    
    func mapResponse(body: String, status: Int? = nil, headers: [String: String]? = nil) {
        guard let flow = selectedFlow,
              let ruleInfo = mapRuleKey(for: flow) else { return }
        let preferredKey = ruleInfo.key
        let key = MapRuleKeyBuilder.disambiguatedKey(preferredKey: preferredKey, existingKeys: Set(rules.keys))
        let rule = MapRule(
            key: key,
            host: ruleInfo.host,
            path: ruleInfo.path,
            scheme: ruleInfo.scheme,
            request: ruleInfo.request,
            body: body,
            status: status ?? flow.response?.status ?? 200,
            headers: headers ?? flow.response?.headers ?? [:]
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

    func isBreakpointEnabled(for flow: MitmFlow, phase: FlowBreakpointPhase) -> Bool {
        guard let info = mapKey(for: flow) else { return false }
        guard let rule = breakpointRules[info.key], rule.isEnabled else { return false }
        switch phase {
        case .request:
            return rule.interceptRequest
        case .response:
            return rule.interceptResponse
        }
    }

    func setBreakpoint(for flow: MitmFlow, phase: FlowBreakpointPhase, enabled: Bool) {
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

    func removeBreakpoint(for flow: MitmFlow) {
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

    func flow(withID id: String) -> MitmFlow? {
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
            let defaultStatus = flow.response?.status ?? 200
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
            guard let request = flow.request else { return }
            let payload = BreakpointRequestPayload(
                method: request.method,
                url: request.url,
                headers: request.headers,
                body: request.body
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .request,
                requestPayload: payload,
                responsePayload: nil
            )
        case .response:
            guard let response = flow.response else { return }
            let payload = BreakpointResponsePayload(
                status: response.status ?? 200,
                headers: response.headers ?? [:],
                body: response.body ?? ""
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
                guard let self else { return }
                self.defaultPort = newPort
                if !self.isRunning {
                    self.activePort = newPort
                }
                self.updateMacOSProxyOverridePort()
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

        settings.$overrideMacOSProxy
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.overrideMacOSProxy = isEnabled
                self.syncMacOSProxyOverride()
            }
            .store(in: &settingsCancellables)

        settings.$alertsEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.alertsEnabled = isEnabled
                if isEnabled {
                    self.seenAlertFlowIDs = Set(self.flows.filter { $0.response != nil }.map(\.id))
                    self.triggeredAlertKeys.removeAll()
                } else {
                    self.seenAlertFlowIDs.removeAll()
                    self.triggeredAlertKeys.removeAll()
                }
            }
            .store(in: &settingsCancellables)

        settings.$alertRules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rules in
                guard let self else { return }
                self.applyAlertRules(rules)
            }
            .store(in: &settingsCancellables)

        defaultPort = settings.defaultPort
        autoClearOnStart = settings.autoClearOnStart
        restrictInterceptionToHosts = settings.restrictInterceptionToActivePinnedHosts
        interceptionHosts = settings.pinnedHosts.filter(\.isActive).map(\.host)
        setTrafficProfile(settings.activeTrafficProfile, force: true)
        overrideMacOSProxy = settings.overrideMacOSProxy
        alertsEnabled = settings.alertsEnabled
        applyAlertRules(settings.alertRules)
        if overrideMacOSProxy {
            applyMacOSProxyOverride(port: activePort)
        }

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

    private func syncMacOSProxyOverride() {
        if overrideMacOSProxy {
            applyMacOSProxyOverride(port: activePort)
        } else {
            clearMacOSProxyOverride()
        }
    }

    private func updateMacOSProxyOverridePort() {
        guard overrideMacOSProxy else { return }
        applyMacOSProxyOverride(port: activePort)
    }

    private func applyMacOSProxyOverride(port: Int) {
        Task { @MainActor [weak self] in
            do {
                try await MacOSProxyOverrideManager.shared.enableProxy(host: "localhost", port: port)
            } catch {
                self?.appendLog("\n[SYSTEM] \(error.localizedDescription)")
            }
        }
    }

    private func clearMacOSProxyOverride() {
        Task { @MainActor [weak self] in
            do {
                try await MacOSProxyOverrideManager.shared.disableProxy()
            } catch {
                self?.appendLog("\n[SYSTEM] \(error.localizedDescription)")
            }
        }
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

    @MainActor
    func addGitCollectionSource(remoteURL: String, reference: String, subdirectory: String?) async throws {
        let trimmedRemote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedReference.isEmpty else { return }

        let source = GitCollectionSource(remoteURL: trimmedRemote, reference: trimmedReference, subdirectory: subdirectory)
        let result = try await collectionStore.syncGitSource(source)

        var persistedSource = source
        persistedSource.lastSyncedAt = result.syncedAt
        persistedSource.lastSyncedCommit = result.commit
        gitCollectionSources.append(persistedSource)
        persistGitSources()
        applyGitCollections(result.collections)
    }

    @MainActor
    func syncGitCollectionSource(_ id: UUID) async throws {
        guard let source = gitCollectionSources.first(where: { $0.id == id }) else { return }
        let result = try await collectionStore.syncGitSource(source)
        var updated = source
        updated.lastSyncedAt = result.syncedAt
        updated.lastSyncedCommit = result.commit
        updateGitSource(updated)
        applyGitCollections(result.collections)
    }

    @MainActor
    func syncAllGitCollectionSources() async throws {
        for source in gitCollectionSources {
            let result = try await collectionStore.syncGitSource(source)
            var updated = source
            updated.lastSyncedAt = result.syncedAt
            updated.lastSyncedCommit = result.commit
            updateGitSource(updated)
            applyGitCollections(result.collections)
        }
    }

    @MainActor
    func removeGitCollectionSource(_ id: UUID) {
        gitCollectionSources.removeAll(where: { $0.id == id })
        persistGitSources()
    }

    @MainActor
    func pushCollectionToGit(
        collectionID: UUID,
        sourceID: UUID,
        branch: String,
        relativePath: String,
        commitMessage: String,
        tagName: String?,
        authorName: String?,
        authorEmail: String?
    ) async throws {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        guard let baseSource = gitCollectionSources.first(where: { $0.id == sourceID }) else { return }

        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty else { return }

        let normalizedPath = Self.normalizedHarPath(relativePath)

        let targetSource = ensureGitSourceForPush(
            baseSource: baseSource,
            branch: trimmedBranch
        )

        let identity = GitCommitIdentity(
            name: Self.normalizedGitIdentityValue(authorName, fallback: "FRTMProxy"),
            email: Self.normalizedGitIdentityValue(authorEmail, fallback: "frtmproxy@localhost")
        )

        let result = try await collectionStore.pushCollectionToGit(
            collections[collectionIndex],
            source: targetSource,
            branch: trimmedBranch,
            relativePath: normalizedPath,
            commitMessage: commitMessage,
            tagName: tagName,
            author: identity
        )

        collections[collectionIndex].origin = MapCollectionOrigin(
            git: GitCollectionOrigin(
                sourceID: targetSource.id,
                remoteURL: targetSource.remoteURL,
                reference: trimmedBranch,
                relativePath: normalizedPath,
                commit: result.commit
            )
        )
        persistCollections()

        var updatedSource = targetSource
        updatedSource.lastSyncedAt = result.pushedAt
        updatedSource.lastSyncedCommit = result.commit
        updateGitSource(updatedSource)
    }

    @MainActor
    private func updateGitSource(_ updated: GitCollectionSource) {
        guard let index = gitCollectionSources.firstIndex(where: { $0.id == updated.id }) else { return }
        gitCollectionSources[index] = updated
        persistGitSources()
    }

    @MainActor
    private func ensureGitSourceForPush(baseSource: GitCollectionSource, branch: String) -> GitCollectionSource {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBranch == baseSource.reference {
            return baseSource
        }

        if let existing = gitCollectionSources.first(where: {
            $0.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines) == baseSource.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                && ($0.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == (baseSource.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                && $0.reference.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedBranch
        }) {
            return existing
        }

        let created = GitCollectionSource(remoteURL: baseSource.remoteURL, reference: trimmedBranch, subdirectory: baseSource.subdirectory)
        gitCollectionSources.append(created)
        persistGitSources()
        return created
    }

    private static func normalizedHarPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".har") {
            return trimmed
        }
        return trimmed + ".har"
    }

    private static func normalizedGitIdentityValue(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    @MainActor
    private func applyGitCollections(_ incoming: [MapCollection]) {
        for newCollection in incoming {
            guard let newOrigin = newCollection.origin?.git else { continue }
            if let existingIndex = collections.firstIndex(where: { $0.origin?.git?.sourceID == newOrigin.sourceID && $0.origin?.git?.relativePath == newOrigin.relativePath }) {
                let preservedID = collections[existingIndex].id
                let preservedCreatedAt = collections[existingIndex].createdAt
                let preservedIsEnabled = collections[existingIndex].isEnabled
                let preservedEnabledAt = collections[existingIndex].enabledAt

                var updated = newCollection
                updated = MapCollection(
                    id: preservedID,
                    name: updated.name,
                    createdAt: preservedCreatedAt,
                    isEnabled: preservedIsEnabled,
                    enabledAt: preservedEnabledAt,
                    rules: updated.rules,
                    origin: updated.origin
                )
                collections[existingIndex] = updated
            } else {
                collections.append(newCollection)
            }
        }
        persistCollections()
        syncAppliedRules()
    }

    private func mapKey(for flow: MitmFlow) -> (key: String, host: String, path: String, scheme: String?)? {
        guard let urlString = flow.request?.url,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        let path = url.path
        return (key: host + path, host: host, path: path.isEmpty ? "/" : path, scheme: url.scheme)
    }

    private func mapRuleKey(for flow: MitmFlow) -> (key: String, host: String, path: String, scheme: String?, request: MapRuleRequest?)? {
        guard let base = mapKey(for: flow) else { return nil }
        guard let request = flow.request else { return nil }
        let fullKey = MapRuleKeyBuilder.makeKey(
            host: base.host,
            path: base.path,
            method: request.method,
            url: request.url,
            headers: request.headers,
            body: request.body
        )
        return (
            key: fullKey,
            host: base.host,
            path: base.path,
            scheme: base.scheme,
            request: MapRuleRequest(method: request.method, url: request.url, headers: request.headers, body: request.body)
        )
    }
    
    private func bind() {
        service.flowsPublisher
            .map { map in
                map.values.sorted(by: { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) })
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sorted in
                guard let self else { return }
                let enriched = self.enrichFlowsWithCachedApps(sorted)
                self.flows = enriched
                if self.selectedFlowID == nil {
                    self.selectedFlowID = enriched.first?.id
                }
                self.captureRecordingRules(from: enriched)
                self.enqueueBreakpointHits(from: enriched)
                self.resolveClientAppsIfNeeded(in: enriched)
                self.processAlerts(in: enriched)
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

    private func enrichFlowsWithCachedApps(_ flows: [MitmFlow]) -> [MitmFlow] {
        var enriched = flows
        for index in enriched.indices {
            guard enriched[index].clientApp == nil,
                  let clientPort = enriched[index].client?.port,
                  !enriched[index].clientIP.isEmpty else {
                continue
            }
            let key = connectionKey(clientIP: enriched[index].clientIP, clientPort: clientPort, proxyPort: activePort)
            if let app = clientAppByConnectionKey[key] {
                enriched[index].clientApp = app
            }
        }
        return enriched
    }

    private func resolveClientAppsIfNeeded(in flows: [MitmFlow]) {
        let proxyPort = activePort
        for flow in flows {
            guard flow.clientApp == nil,
                  let clientPort = flow.client?.port,
                  isLoopbackClientIP(flow.clientIP) else {
                continue
            }

            let key = connectionKey(clientIP: flow.clientIP, clientPort: clientPort, proxyPort: proxyPort)
            if resolvingConnectionKeys.contains(key) || clientAppByConnectionKey[key] != nil {
                continue
            }
            resolvingConnectionKeys.insert(key)

            Task.detached { [weak self] in
                guard let self else { return }
                let app = await self.clientAppResolver.resolve(clientPort: clientPort, proxyPort: proxyPort)
                await MainActor.run {
                    self.resolvingConnectionKeys.remove(key)
                    guard let app else { return }
                    self.clientAppByConnectionKey[key] = app
                    var updated = self.flows
                    var changed = false
                    for idx in updated.indices where updated[idx].clientApp == nil {
                        guard let existingPort = updated[idx].client?.port else { continue }
                        let existingKey = self.connectionKey(clientIP: updated[idx].clientIP, clientPort: existingPort, proxyPort: proxyPort)
                        if existingKey == key {
                            updated[idx].clientApp = app
                            changed = true
                        }
                    }
                    if changed {
                        self.flows = updated
                    }
                }
            }
        }
    }

    private func connectionKey(clientIP: String, clientPort: Int, proxyPort: Int) -> String {
        "\(clientIP.trimmingCharacters(in: .whitespacesAndNewlines))|\(clientPort)|\(proxyPort)"
    }

    private func isLoopbackClientIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "::1" || trimmed == "localhost" {
            return true
        }
        return trimmed.hasPrefix("127.")
    }

    private func applyAlertRules(_ rules: [AlertRule]) {
        let trimmed: [AlertRule] = rules.map {
            AlertRule(
                id: $0.id,
                name: $0.name,
                query: $0.query,
                isEnabled: $0.isEnabled,
                createdAt: $0.createdAt
            )
        }

        let previousQueries = alertRuleQueryByID
        alertRuleQueryByID = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.id, $0.query) })

        let currentIDs = Set(trimmed.map(\.id))
        let removedIDs = Set(previousQueries.keys).subtracting(currentIDs)
        if !removedIDs.isEmpty {
            for id in removedIDs {
                removeTriggeredAlerts(forRuleID: id)
            }
        }

        for rule in trimmed {
            let previous = previousQueries[rule.id]
            if let previous, previous != rule.query {
                removeTriggeredAlerts(forRuleID: rule.id)
            }
        }

        alertRules = trimmed
        alertFiltersByRuleID = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.id, FlowFilter(searchText: $0.query)) })
    }

    private func removeTriggeredAlerts(forRuleID id: UUID) {
        let prefix = id.uuidString + "|"
        triggeredAlertKeys = Set(triggeredAlertKeys.filter { !$0.hasPrefix(prefix) })
    }

    private func processAlerts(in flows: [MitmFlow]) {
        guard alertsEnabled else { return }
        guard !alertRules.isEmpty else { return }

        let enabledRules = alertRules.filter(\.isEnabled)
        guard !enabledRules.isEmpty else { return }

        let candidates = flows.filter { $0.response != nil && !seenAlertFlowIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        for rule in enabledRules {
            let filter = alertFiltersByRuleID[rule.id] ?? FlowFilter(searchText: rule.query)
            let matching = filter.apply(to: candidates)
            for flow in matching {
                let key = rule.id.uuidString + "|" + flow.id
                guard !triggeredAlertKeys.contains(key) else { continue }
                triggeredAlertKeys.insert(key)
                notifyAlert(rule: rule, flow: flow)
            }
        }

        seenAlertFlowIDs.formUnion(candidates.map(\.id))
        if seenAlertFlowIDs.count > 2_000 {
            let responseFlowIDs = Set(flows.filter { $0.response != nil }.map(\.id))
            seenAlertFlowIDs = seenAlertFlowIDs.intersection(responseFlowIDs)
        }

        if triggeredAlertKeys.count > 20_000 {
            triggeredAlertKeys.removeAll()
        }
    }

    private func notifyAlert(rule: AlertRule, flow: MitmFlow) {
        let title = rule.name.isEmpty ? "FRTMProxy Alert" : rule.name
        let method = flow.request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let url = flow.request?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = flow.response?.status.map(String.init) ?? "—"
        let client = flow.clientIP

        var body = ""
        if !method.isEmpty && !url.isEmpty {
            body = "\(method) \(url)"
        } else if !url.isEmpty {
            body = url
        } else {
            body = flow.sharePreviewTitle
        }
        body += "\nStatus: \(status)"
        if !client.isEmpty {
            body += "\nClient: \(client)"
        }

        Task {
            await AlertNotificationService.shared.postAlertNotification(title: title, body: body)
        }
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

    private func loadPersistedGitSources() {
        gitCollectionSources = collectionStore.loadGitSources()
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

    private func persistGitSources() {
        collectionStore.saveGitSources(gitCollectionSources)
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

    private func captureRecordingRules(from flows: [MitmFlow]) {
        guard collectionRecorder.isRecording else { return }
        let candidates = flows
            .filter { !recordedFlowIDs.contains($0.id) && $0.response != nil }
            .sorted(by: { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) })

        var existingKeys = Set(collectionRecorder.currentRules().map(\.key))
        for flow in candidates {
            guard let response = flow.response,
                  let info = mapRuleKey(for: flow) else { continue }

            let key = MapRuleKeyBuilder.disambiguatedKey(preferredKey: info.key, existingKeys: existingKeys)
            existingKeys.insert(key)
            let rule = MapRule(
                key: key,
                host: info.host,
                path: info.path,
                scheme: info.scheme,
                request: info.request,
                body: response.body ?? "",
                status: response.status ?? 200,
                headers: response.headers ?? [:],
                isEnabled: true
            )
            record(rule: rule)
            recordedFlowIDs.insert(flow.id)
        }
    }

    private func syncAppliedRules() {
        var merged: [String: MapRule] = [:]
        var orderedKeys: [String] = []

        func upsert(_ rule: MapRule) {
            if let index = orderedKeys.firstIndex(of: rule.key) {
                orderedKeys.remove(at: index)
            }
            orderedKeys.append(rule.key)
            merged[rule.key] = rule
        }

        for rule in rules.values.sorted(by: { $0.key < $1.key }) where rule.isEnabled {
            upsert(rule)
        }

        let enabledCollections = collections
            .filter { $0.isEnabled }
            .sorted(by: { ($0.enabledAt ?? Date.distantPast) < ($1.enabledAt ?? Date.distantPast) })

        for collection in enabledCollections {
            for rule in collection.rules where rule.isEnabled {
                upsert(rule)
            }
        }

        let oldKeys = Set(appliedRules.keys)
        let newKeys = Set(merged.keys)
        let removedKeys = oldKeys.subtracting(newKeys)
        for key in removedKeys {
            service.deleteRule(forKey: key)
        }

        for key in orderedKeys {
            guard let rule = merged[key] else { continue }
            if let existing = appliedRules[key], existing == rule {
                continue
            }
            service.mockRule(rule)
        }

        appliedRules = merged
    }

    private func syncBreakpointRules() {
        let activeRules = breakpointRules.values.filter { $0.isEnabled && ($0.interceptRequest || $0.interceptResponse) }
        var merged: [String: FlowBreakpointRule] = [:]
        for rule in activeRules {
            merged[rule.key] = rule
        }

        let oldKeys = Set(appliedBreakpointRules.keys)
        let newKeys = Set(merged.keys)

        let removedKeys = oldKeys.subtracting(newKeys)
        for key in removedKeys {
            service.deleteBreakpointRule(forKey: key)
        }

        for (key, rule) in merged {
            if let existing = appliedBreakpointRules[key], existing == rule {
                continue
            }
            service.updateBreakpointRule(rule)
        }

        appliedBreakpointRules = merged
    }

    private func enqueueBreakpointHits(from flows: [MitmFlow]) {
        var waitingIDs: Set<String> = []

        for flow in flows {
            guard let breakpoint = flow.breakpoint,
                  breakpoint.state == .waiting else { continue }

            let hit = FlowBreakpointHit(
                flowID: flow.id,
                phase: breakpoint.phase,
                key: breakpoint.key,
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
