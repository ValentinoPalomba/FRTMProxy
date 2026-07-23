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
    var isStartingProxy = false
    var captureSessionLoadTask: Task<Void, Never>?
    var captureSessionCloseTask: Task<Void, Never>?
    lazy var sessionCaptureWriter: SessionCaptureWriter? = sessionStore.map(SessionCaptureWriter.init(store:))

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
        guard !isRunning, !isStartingProxy else { return }
        isStartingProxy = true
        defer { isStartingProxy = false }
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
        } catch {
            logText.append("\n\(error.localizedDescription)")
            onToast?("Failed to start proxy: \(error.localizedDescription)", .error)
        }
    }

    @MainActor
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

        private struct PendingFlows {
            private(set) var orderedKeys: [FlowKey] = []
            private(set) var flowsByKey: [FlowKey: MitmFlow] = [:]

            mutating func append(_ flow: MitmFlow, sessionID: UUID) {
                let key = FlowKey(sessionID: sessionID, flowID: flow.id)
                if let existing = flowsByKey[key] {
                    flowsByKey[key] = existing.mergingSessionSnapshot(with: flow)
                } else {
                    orderedKeys.append(key)
                    flowsByKey[key] = flow
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
        private let signalContinuation: AsyncStream<Void>.Continuation
        private let updatesSubject = PassthroughSubject<Update, Never>()
        private var consumerTask: Task<Void, Never>?
        private var pendingErrorsBySession: [UUID: any Error] = [:]

        var updatesPublisher: AnyPublisher<Update, Never> {
            updatesSubject.eraseToAnyPublisher()
        }

        init(store: any SessionStoreProtocol) {
            self.store = store
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

        func enqueue(_ flow: MitmFlow, sessionID: UUID) {
            lock.withLock {
                if case var .flows(pending)? = pendingEvents.last {
                    pending.append(flow, sessionID: sessionID)
                    pendingEvents[pendingEvents.index(before: pendingEvents.endIndex)] = .flows(pending)
                } else {
                    var pending = PendingFlows()
                    pending.append(flow, sessionID: sessionID)
                    pendingEvents.append(.flows(pending))
                }
            }
            signalContinuation.yield()
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
            let events = lock.withLock {
                let snapshot = pendingEvents
                pendingEvents.removeAll(keepingCapacity: true)
                return snapshot
            }
            guard !events.isEmpty else { return }

            var index = events.startIndex
            while index < events.endIndex {
                switch events[index] {
                case let .flows(pending):
                    for sessionID in pending.sessionIDs {
                        let flows = pending.flows(for: sessionID)
                        do {
                            let summary = try await store.upsert(flows: flows, in: sessionID)
                            pendingErrorsBySession[sessionID] = nil
                            updatesSubject.send(Update(
                                sessionID: sessionID,
                                insertedFlowCount: summary.insertedFlowCount,
                                updatedAt: summary.latestFlowDate
                                    ?? flows.compactMap(Self.sortTimestamp).max()
                                    ?? .now,
                                errorDescription: nil
                            ))
                        } catch {
                            pendingErrorsBySession[sessionID] = error
                            requeue(flows: flows, sessionID: sessionID)
                            updatesSubject.send(Update(
                                sessionID: sessionID,
                                insertedFlowCount: 0,
                                updatedAt: .now,
                                errorDescription: error.localizedDescription
                            ))
                        }
                    }
                    index += 1

                case let .flush(sessionID, continuation):
                    if let error = pendingErrorsBySession[sessionID] {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                    index += 1
                }
            }
        }

        private func requeue(flows: [MitmFlow], sessionID: UUID) {
            guard !flows.isEmpty else { return }
            var failed = PendingFlows()
            for flow in flows {
                failed.append(flow, sessionID: sessionID)
            }
            lock.withLock {
                if case let .flows(newer)? = pendingEvents.first {
                    failed.appendNewerContents(of: newer)
                    pendingEvents[0] = .flows(failed)
                } else {
                    pendingEvents.insert(.flows(failed), at: 0)
                }
            }
        }

        private static func sortTimestamp(_ flow: MitmFlow) -> Date? {
            let timestamp = flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp
            return timestamp.map(Date.init(timeIntervalSince1970:))
        }
    }
}
