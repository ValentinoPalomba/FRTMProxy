import Combine
import Foundation
import AppKit
import Network

@MainActor
final class ProxyViewModel: ObservableObject {
    @Published var flows: [MitmFlow] = [] {
        didSet {
            if let selected = flows.first(where: { $0.id == selectedFlowID }) {
                retainSelectedFlow(selected, merging: false, notify: false)
            }
        }
    }
    @Published var selectedFlowID: String? {
        didSet {
            guard selectedFlowID != oldValue else { return }
            selectedFlowSnapshot = nil
            if let selected = flows.first(where: { $0.id == selectedFlowID }) {
                retainSelectedFlow(selected, merging: false, notify: false)
            }
        }
    }
    private var selectedFlowSnapshot: MitmFlow?
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
    var sessionStore: (any SessionStoreProtocol)?
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
    var isStartingProxy = false
    var captureSessionLoadTask: Task<Void, Never>?
    var captureSessionCloseTask: Task<Void, Never>?
    var sessionCaptureWriter: SessionCaptureWriter?
    private var proxyStartGeneration = UUID()

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
        self.sessionStore = sessionStore
        self.sessionCaptureWriter = sessionStore.map { SessionCaptureWriter(store: $0) }
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
        loadCaptureSessions()
    }

    nonisolated static func makeDefaultSessionStore() throws -> any SessionStoreProtocol {
        let databaseURL = CaptureStorageConfiguration.root
            .appending(path: "FRTMProxy", directoryHint: .isDirectory)
            .appending(path: "Sessions", directoryHint: .isDirectory)
            .appending(path: "sessions.sqlite")
        return try SQLiteSessionStore(databaseURL: databaseURL, keyProvider: CaptureStorageConfiguration.keyProvider)
    }

    func installSessionStore(_ store: any SessionStoreProtocol) {
        sessionStore = store
        sessionCaptureWriter = SessionCaptureWriter(store: store)
        bindSessionWriterUpdates()
    }

    deinit {
        networkPathMonitor?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    var selectedFlow: MitmFlow? {
        selectedFlowSnapshot ?? flows.first(where: { $0.id == selectedFlowID })
    }

    // One retained value keeps the inspector readable when the rolling live window evicts it.
    // Strings and arrays share storage with the live value until an update mutates them.
    func retainSelectedFlow(_ incoming: MitmFlow, merging: Bool = true, notify: Bool = true) {
        guard incoming.id == selectedFlowID else { return }
        var snapshot = merging ? selectedFlowSnapshot?.mergingSessionSnapshot(with: incoming) ?? incoming : incoming
        snapshot.livePreviewWarning = incoming.livePreviewWarning ?? snapshot.livePreviewWarning
        _ = LiveFlowMemoryBudget.trimWebSocket(&snapshot)
        if LiveFlowMemoryBudget.cost(snapshot) > LiveFlowMemoryBudget.maximumBytes {
            // Keep the previous readable value instead of retaining an unbounded event graph.
            var previous = selectedFlowSnapshot ?? MitmFlow(id: incoming.id, event: incoming.event)
            previous.livePreviewWarning = String(localized: "Selected live preview exceeds 64 MiB. The last bounded preview is retained; open the recorded session for newer data.", bundle: AppLocalization.bundle)
            snapshot = previous
        }
        if notify { objectWillChange.send() }
        selectedFlowSnapshot = snapshot
    }

    var orderedBreakpointRules: [FlowBreakpointRule] {
        breakpointRules.values.sorted(by: { $0.key < $1.key })
    }

    @MainActor
    func startProxy(port: Int? = nil) async {
        guard !isRunning, !isStartingProxy else { return }
        isStartingProxy = true
        let startGeneration = UUID()
        proxyStartGeneration = startGeneration
        defer { isStartingProxy = false }
        if autoClearOnStart {
            clear()
        }
        let selectedPort = port ?? defaultPort
        do {
            guard await ensureCaptureSession() else { return }
            guard proxyStartGeneration == startGeneration, !Task.isCancelled else { return }
            try await service.startProxy(
                port: selectedPort,
                restrictToHosts: restrictInterceptionToHosts,
                hosts: interceptionHosts
            )
            guard proxyStartGeneration == startGeneration, !Task.isCancelled else { return }
            activePort = selectedPort
            isRunning = true
            updateMacOSProxyOverridePort()
            reapplyStoredRules()
        } catch {
            guard proxyStartGeneration == startGeneration, !Task.isCancelled else { return }
            logText.append("\n\(error.localizedDescription)")
            onToast?("Failed to start proxy: \(error.localizedDescription)", .error)
        }
    }

    @MainActor
    func stopProxy() {
        proxyStartGeneration = UUID()
        service.stopProxy()
        isRunning = false
        syncMacOSProxyOverride()
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

    final class SessionCaptureWriter: @unchecked Sendable {
        struct Update: Sendable {
            let sessionID: UUID
            let insertedFlowCount: Int
            let updatedAt: Date
            let errorDescription: String?
        }

        private struct FlowKey: Hashable {
            let sessionID: UUID
            let flowID: String
        }

        enum CapacityError: LocalizedError {
            case saturated
            var errorDescription: String? {
                String(localized: "Capture stopped: session writer queue is full. This session is incomplete; accepted data remains available for retry.", bundle: AppLocalization.bundle)
            }
        }

        private struct PendingFlows {
            private(set) var byteCount = 0
            private(set) var orderedKeys: [FlowKey] = []
            private(set) var flowsByKey: [FlowKey: MitmFlow] = [:]

            func preparedAppend(of flow: MitmFlow, sessionID: UUID) -> (flow: MitmFlow, bytes: Int, flows: Int) {
                let key = FlowKey(sessionID: sessionID, flowID: flow.id)
                guard let existing = flowsByKey[key] else { return (flow, LiveFlowMemoryBudget.cost(flow), 1) }
                let merged = existing.mergingSessionSnapshot(with: flow)
                return (merged, LiveFlowMemoryBudget.cost(merged) - LiveFlowMemoryBudget.cost(existing), 0)
            }

            mutating func appendPrepared(_ flow: MitmFlow, sessionID: UUID, additionalBytes: Int) {
                let key = FlowKey(sessionID: sessionID, flowID: flow.id)
                if flowsByKey[key] == nil { orderedKeys.append(key) }
                flowsByKey[key] = flow
                byteCount += additionalBytes
            }

            mutating func append(_ flow: MitmFlow, sessionID: UUID) {
                let key = FlowKey(sessionID: sessionID, flowID: flow.id)
                if let existing = flowsByKey[key] {
                    let merged = existing.mergingSessionSnapshot(with: flow)
                    byteCount += LiveFlowMemoryBudget.cost(merged) - LiveFlowMemoryBudget.cost(existing)
                    flowsByKey[key] = merged
                } else {
                    orderedKeys.append(key)
                    flowsByKey[key] = flow
                    byteCount += LiveFlowMemoryBudget.cost(flow)
                }
            }

            func flows(for sessionID: UUID) -> [MitmFlow] {
                orderedKeys.compactMap { key in
                    guard key.sessionID == sessionID else { return nil }
                    return flowsByKey[key]
                }
            }

            var sessionIDs: [UUID] {
                var seen = Set<UUID>()
                return orderedKeys.compactMap { key in
                    seen.insert(key.sessionID).inserted ? key.sessionID : nil
                }
            }

            mutating func appendNewerContents(of newer: PendingFlows) {
                for key in newer.orderedKeys {
                    guard let flow = newer.flowsByKey[key] else { continue }
                    append(flow, sessionID: key.sessionID)
                }
            }
        }

        private enum Event: @unchecked Sendable {
            case flows(PendingFlows)
            case flush(UUID, CheckedContinuation<Void, any Error>)
        }

        private let store: any SessionStoreProtocol
        private let lock = NSLock()
        private var pendingEvents: [Event] = []
        private let maximumQueuedBytes: Int
        private let maximumQueuedFlows: Int
        private var retainedBytes = 0
        private var retainedFlows = 0
        private var saturatedSessions = Set<UUID>()

        var queueUsage: (bytes: Int, flows: Int) {
            lock.withLock { (retainedBytes, retainedFlows) }
        }
        private let signalContinuation: AsyncStream<Void>.Continuation
        private let updatesSubject = PassthroughSubject<Update, Never>()
        private var consumerTask: Task<Void, Never>?
        private var pendingErrorsBySession: [UUID: any Error] = [:]
        private var failedFlowIDsBySession: [UUID: Set<String>] = [:]

        var updatesPublisher: AnyPublisher<Update, Never> {
            updatesSubject.eraseToAnyPublisher()
        }

        init(store: any SessionStoreProtocol, maximumQueuedBytes: Int = 64 * 1024 * 1024, maximumQueuedFlows: Int = 4096) {
            self.store = store
            self.maximumQueuedBytes = max(1, maximumQueuedBytes)
            self.maximumQueuedFlows = max(1, maximumQueuedFlows)
            let streamAndContinuation = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            signalContinuation = streamAndContinuation.continuation
            consumerTask = Task { [weak self] in
                for await _ in streamAndContinuation.stream {
                    do {
                        try await Task.sleep(for: .milliseconds(120))
                    } catch {
                        return
                    }
                    await self?.persistPendingEvents()
                }
            }
        }

        deinit {
            signalContinuation.finish()
            consumerTask?.cancel()
        }

        @discardableResult
        func enqueue(_ flow: MitmFlow, sessionID: UUID) -> Bool {
            let accepted = lock.withLock {
                guard !saturatedSessions.contains(sessionID) else { return false }
                var pending = PendingFlows()
                // Remove the tail before mutation so its dictionary has one owner.
                // Keeping the old event in the array causes a full COW copy per flow.
                if case .flows? = pendingEvents.last,
                   case let .flows(previous) = pendingEvents.removeLast() {
                    pending = previous
                }
                let delta = pending.preparedAppend(of: flow, sessionID: sessionID)
                let bytes = retainedBytes + delta.bytes
                let count = retainedFlows + delta.flows
                guard bytes <= maximumQueuedBytes, count <= maximumQueuedFlows else {
                    if !pending.orderedKeys.isEmpty { pendingEvents.append(.flows(pending)) }
                    saturatedSessions.insert(sessionID)
                    return false
                }
                pending.appendPrepared(delta.flow, sessionID: sessionID, additionalBytes: delta.bytes)
                retainedBytes = bytes
                retainedFlows = count
                pendingEvents.append(.flows(pending))
                return true
            }
            if accepted { signalContinuation.yield() }
            return accepted
        }

        func flush(sessionID: UUID) async throws {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    pendingEvents.append(.flush(sessionID, continuation))
                }
                signalContinuation.yield()
            }
        }

        private func persistPendingEvents() async {
            var events = lock.withLock {
                let snapshot = pendingEvents
                pendingEvents.removeAll(keepingCapacity: true)
                return snapshot
            }
            guard !events.isEmpty else { return }

            var releasedBytes = 0
            var releasedFlows = 0
            var barriers: [(CheckedContinuation<Void, any Error>, (any Error)?)] = []
            var index = events.startIndex
            while index < events.endIndex {
                switch events[index] {
                case let .flows(pending):
                    for sessionID in pending.sessionIDs {
                        let flows = pending.flows(for: sessionID)
                        for batch in Self.batches(flows) {
                            do {
                                let summary = try await store.upsert(flows: batch, in: sessionID)
                                releasedBytes += batch.reduce(0) { $0 + LiveFlowMemoryBudget.cost($1) }
                                releasedFlows += batch.count
                                failedFlowIDsBySession[sessionID]?.subtract(batch.map(\.id))
                                if failedFlowIDsBySession[sessionID]?.isEmpty != false {
                                    failedFlowIDsBySession[sessionID] = nil
                                    pendingErrorsBySession[sessionID] = nil
                                }
                                updatesSubject.send(Update(
                                    sessionID: sessionID,
                                    insertedFlowCount: summary.insertedFlowCount,
                                    updatedAt: summary.latestFlowDate ?? batch.compactMap(Self.sortTimestamp).max() ?? .now,
                                    errorDescription: nil
                                ))
                            } catch {
                                pendingErrorsBySession[sessionID] = error
                                failedFlowIDsBySession[sessionID, default: []].formUnion(batch.map(\.id))
                                let reclaimed = requeue(flows: batch, sessionID: sessionID)
                                releasedBytes += reclaimed.bytes
                                releasedFlows += reclaimed.flows
                                updatesSubject.send(Update(sessionID: sessionID, insertedFlowCount: 0,
                                    updatedAt: .now, errorDescription: error.localizedDescription))
                            }
                        }

                    }
                    index += 1

                case let .flush(sessionID, continuation):
                    barriers.append((continuation, pendingErrorsBySession[sessionID]))
                    index += 1
                }
            }
            // Snapshot references must be dropped before admitting more payloads.
            events.removeAll()
            lock.withLock {
                retainedBytes -= releasedBytes
                retainedFlows -= releasedFlows
            }
            for (continuation, error) in barriers {
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }

        static func batches(_ flows: [MitmFlow]) -> [[MitmFlow]] {
            var result: [[MitmFlow]] = [], batch: [MitmFlow] = []
            var bytes = 0
            for flow in flows {
                let cost = LiveFlowMemoryBudget.cost(flow)
                if !batch.isEmpty, batch.count >= 128 || bytes + cost > 16 * 1024 * 1024 {
                    result.append(batch)
                    batch = []
                    bytes = 0
                }
                batch.append(flow)
                bytes += cost
            }
            if !batch.isEmpty { result.append(batch) }
            return result
        }

        private func requeue(flows: [MitmFlow], sessionID: UUID) -> (bytes: Int, flows: Int) {
            guard !flows.isEmpty else { return (0, 0) }
            var failed = PendingFlows()
            for flow in flows {
                failed.append(flow, sessionID: sessionID)
            }
            return lock.withLock {
                if case let .flows(newer)? = pendingEvents.first {
                    let beforeBytes = failed.byteCount + newer.byteCount
                    let beforeCount = failed.orderedKeys.count + newer.orderedKeys.count
                    failed.appendNewerContents(of: newer)
                    pendingEvents[0] = .flows(failed)
                    return (beforeBytes - failed.byteCount, beforeCount - failed.orderedKeys.count)
                } else {
                    pendingEvents.insert(.flows(failed), at: 0)
                    return (0, 0)
                }
            }
        }

        private static func sortTimestamp(_ flow: MitmFlow) -> Date? {
            let timestamp = flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp
            return timestamp.map(Date.init(timeIntervalSince1970:))
        }
    }
}
