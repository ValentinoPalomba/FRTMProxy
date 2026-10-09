import Combine
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Selected live inspector")
struct SelectedLiveInspectorTests {
    @Test("Selected inspector survives live eviction, receives events, and resets on clear or selection change")
    @MainActor
    func selectedInspectorSurvivesLiveEviction() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "frtm-selected-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: CaptureStorageConfiguration.keyProvider)
        let service = TrafficRuleProxyServiceSpy()
        let model = ProxyViewModel(service: service, sessionStore: store)
        await model.captureSessionLoadTask?.value
        // Allow the initial empty live publisher to settle before exercising eviction.
        try await Task.sleep(for: .milliseconds(150))
        var selected = MitmFlow(id: "selected", event: "request")
        selected.request = .init(method: "GET", url: "https://example.test/selected", headers: [:], body: "request")
        model.flows = [selected]
        model.selectedFlowID = selected.id
        model.flows = (0..<500).map { MitmFlow(id: "new-\($0)", event: "response") }
        #expect(model.selectedFlow?.request?.body == "request")
        var response = MitmFlow(id: selected.id, event: "response")
        response.response = .init(status: 201, headers: [:], body: "updated")
        service.emit(response)
        let deadline = ContinuousClock.now + .seconds(2)
        while model.selectedFlow?.response?.status != 201, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.selectedFlow?.response?.body == "updated")
        #expect(model.selectedFlow?.request?.body == "request")
        var current = response
        current.request = selected.request
        current.response = .init(status: 202, headers: [:], body: "live update")
        model.flows = [current]
        #expect(model.selectedFlow?.response?.status == 202)
        var oversized = MitmFlow(id: selected.id, event: "response")
        oversized.response = .init(status: 203, headers: [:], body: String(repeating: "x", count: LiveFlowMemoryBudget.maximumBytes))
        model.retainSelectedFlow(oversized)
        #expect(model.selectedFlow?.response?.status == 202)
        #expect(model.selectedFlow?.livePreviewWarning?.contains("64 MiB") == true)
        #expect(LiveFlowMemoryBudget.cost(try #require(model.selectedFlow)) <= LiveFlowMemoryBudget.maximumBytes)
        model.flows = [MitmFlow(id: "other", event: "request")]
        model.selectedFlowID = "other"
        #expect(model.selectedFlow?.id == "other")
        #expect(model.selectedFlow?.response == nil)
        model.retainSelectedFlow(response)
        #expect(model.selectedFlow?.id == "other")
        model.clear()
        model.retainSelectedFlow(current)
        #expect(model.selectedFlowID == nil)
        #expect(model.selectedFlow == nil)
    }

}

@Suite("Legacy traffic rule adapter")
struct LegacyTrafficRuleAdapterTests {
    @Test("Unexpected engine exit drains accepted rows, closes incomplete history, and creates a fresh capture")
    @MainActor
    func unexpectedExitPreservesAcceptedWriterRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "frtm-crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: CaptureStorageConfiguration.keyProvider)
        let session = try await store.createSession(name: "Crash fixture")
        let service = TrafficRuleProxyServiceSpy()
        let model = ProxyViewModel(service: service, sessionStore: store)
        await model.captureSessionLoadTask?.value
        service.emitRunning(true)
        var deadline = ContinuousClock.now + .seconds(3)
        while !model.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(model.isRunning)
        let writer = try #require(model.sessionCaptureWriter)
        for index in 0..<3 { #expect(writer.enqueue(MitmFlow(id: "accepted-\(index)", event: "response"), sessionID: session.id)) }
        service.emitRunning(false)
        deadline = ContinuousClock.now + .seconds(3)
        while model.activeCaptureSessionID != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        await model.captureSessionCloseTask?.value
        let interrupted = try #require(try await store.session(id: session.id))
        #expect(!interrupted.isActive)
        #expect(interrupted.incompleteReason != nil)
        #expect(interrupted.flowCount == 3)
        #expect(writer.queueUsage.flows == 0)
        for index in 0..<3 { #expect(try await store.flow(id: "accepted-\(index)", in: session.id) != nil) }
        #expect(await model.ensureCaptureSession())
        #expect(model.activeCaptureSessionID != nil && model.activeCaptureSessionID != session.id)
    }

    @Test("Stopped asynchronous startup cannot restore running state or reapply rules")
    @MainActor
    func stopDuringServiceStartupRejectsStaleCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "frtm-start-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: CaptureStorageConfiguration.keyProvider)
        let service = TrafficRuleProxyServiceSpy()
        let gate = ProxyServiceStartGate()
        service.startGate = gate
        let model = ProxyViewModel(service: service, sessionStore: store)
        await model.captureSessionLoadTask?.value
        let start = Task { @MainActor in await model.startProxy(port: 18888) }
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await gate.hasStarted), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let started = await gate.hasStarted
        model.stopProxy()
        // Loading persisted rules legitimately synchronizes even an empty document.
        // The stale completion must add no further synchronization after Stop.
        let documentsBeforeCompletion = service.replacedDocuments.count
        await gate.finish()
        await start.value
        await model.captureSessionCloseTask?.value
        try #require(started)
        #expect(!model.isRunning)
        #expect(!model.isStartingProxy)
        #expect(service.stopCount == 1)
        #expect(service.replacedDocuments.count == documentsBeforeCompletion)
        #expect(model.activeCaptureSessionID == nil)
    }

    @Test("Writer saturation stops capture and persists an incomplete session")
    @MainActor
    func captureSaturationBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "frtm-saturation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: CaptureStorageConfiguration.keyProvider)
        let session = try await store.createSession(name: "Saturation fixture")
        let service = TrafficRuleProxyServiceSpy()
        let model = ProxyViewModel(service: service, sessionStore: store)
        await model.captureSessionLoadTask?.value
        model.sessionCaptureWriter = ProxyViewModel.SessionCaptureWriter(store: store, maximumQueuedFlows: 1)
        model.isRunning = true
        var toast: String?
        model.onToast = { message, _ in toast = message }
        service.emit(MitmFlow(id: "accepted", event: "response"))
        service.emit(MitmFlow(id: "overflow", event: "response"))
        let deadline = ContinuousClock.now + .seconds(3)
        while service.stopCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.captureSessionCloseTask?.value
        #expect(service.stopCount == 1)
        #expect(!model.isRunning)
        #expect(toast == ProxyViewModel.SessionCaptureWriter.CapacityError.saturated.localizedDescription)
        let stored = try await store.session(id: session.id)
        #expect(stored?.incompleteReason != nil)
        #expect(stored?.isActive == false)
        #expect(stored?.flowCount == 1)
        #expect(try await store.flow(id: "accepted", in: session.id) != nil)
        #expect(try await store.flow(id: "overflow", in: session.id) == nil)
    }

    @Test("Map Local diventa una mock action deterministica")
    func mapLocal() {
        let rule = MapRule(key: "api.example.com/users", host: "api.example.com", path: "/users", body: "{}", status: 201, headers: [:])
        let first = LegacyTrafficRuleAdapter.document(mapRules: [rule], breakpoints: [], scripts: [])
        let second = LegacyTrafficRuleAdapter.document(mapRules: [rule], breakpoints: [], scripts: [])
        #expect(first == second)
        #expect(first.rules.first?.id.uuidString == "C3A5B446-35AB-54BE-A8B2-7384BD4B6F9D")
        #expect(first.rules.first?.matcher.host?.value == "api.example.com")
        if case .mock(let action) = first.rules.first?.actions.first {
            #expect(action.status == 201)
        } else {
            Issue.record("Expected a mock action")
        }
    }

    @Test("Method-scoped breakpoints retain legacy compatibility and unique rule identities")
    func methodScopedBreakpoints() throws {
        let host = "api.example.com"
        let path = "/users"
        let baseKey = FlowBreakpointRule.key(host: host, path: path, method: nil)
        let getKey = FlowBreakpointRule.key(host: host, path: path, method: "get")
        let postKey = FlowBreakpointRule.key(host: host, path: path, method: "POST")
        #expect(baseKey == "api.example.com/users")
        #expect(getKey == "api.example.com/users#method=GET")
        #expect(postKey != getKey)

        let legacyData = Data(#"{"key":"api.example.com/users","host":"api.example.com","path":"/users","scheme":"https","interceptRequest":true,"interceptResponse":false}"#.utf8)
        let legacy = try JSONDecoder().decode(FlowBreakpointRule.self, from: legacyData)
        #expect(legacy.method == nil)
        #expect(legacy.key == baseKey)

        let post = FlowBreakpointRule(key: postKey, host: host, path: path, scheme: "https", interceptRequest: true, interceptResponse: false, method: "post")
        let get = FlowBreakpointRule(key: getKey, host: host, path: path, scheme: "https", interceptRequest: true, interceptResponse: false, method: "GET")
        #expect(post.method == "POST")
        let restored = try JSONDecoder().decode(FlowBreakpointRule.self, from: JSONEncoder().encode(post))
        #expect(restored == post)

        let document = LegacyTrafficRuleAdapter.document(mapRules: [], breakpoints: [legacy, post, get], scripts: [])
        #expect(document.rules.count == 3)
        #expect(Set(document.rules.map(\.id)).count == 3)
        #expect(document.rules.first { $0.name.contains("POST") }?.matcher.method?.value == "POST")
        #expect(document.rules.first { $0.name.contains("GET") }?.matcher.method?.value == "GET")
        #expect(document.rules.first { $0.name == "Breakpoint · api.example.com/users" }?.matcher.method == nil)
    }

    @Test("Legacy mutations replace stale migrated content without changing unified order")
    @MainActor
    func effectiveDocumentSync() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EffectiveRuleSync-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let initialRule = MapRule(
            key: "api.example.com/users",
            host: "api.example.com",
            path: "/users",
            body: "{}",
            status: 200,
            headers: [:]
        )
        let migratedRule = try #require(
            LegacyTrafficRuleAdapter.document(
                mapRules: [initialRule],
                breakpoints: [],
                scripts: []
            ).rules.first
        )
        let firstUnifiedRule = TrafficRule(
            name: "First",
            priority: 0,
            matcher: .init(host: .init(value: "first.example.com")),
            actions: [.block(.init(
                id: UUID(),
                status: 403,
                headers: [:],
                body: ""
            ))]
        )
        var staleMigratedRule = migratedRule
        staleMigratedRule.priority = 1
        staleMigratedRule.isEnabled = true
        staleMigratedRule.actions = [.mock(.init(
            id: try #require(migratedRule.actions.first).id,
            status: 200,
            headers: [:],
            body: "stale"
        ))]
        let lastUnifiedRule = TrafficRule(
            name: "Last",
            priority: 2,
            matcher: .init(host: .init(value: "last.example.com")),
            actions: [.delay(.init(
                id: UUID(),
                requestMilliseconds: 25,
                responseMilliseconds: 0
            ))]
        )
        let trafficRuleStore = TrafficRuleStore(directoryURL: directory)
        try trafficRuleStore.save(rules: [
            firstUnifiedRule,
            staleMigratedRule,
            lastUnifiedRule
        ])
        let service = TrafficRuleProxyServiceSpy()
        let viewModel = ProxyViewModel(
            service: service,
            ruleStore: TrafficRuleMapStoreStub(rules: [initialRule]),
            collectionStore: MapCollectionStore(filename: "rule-sync-\(UUID().uuidString).json"),
            breakpointStore: TrafficRuleBreakpointStoreStub(),
            scriptStore: ScriptStore(filename: "rule-sync-\(UUID().uuidString).json"),
            sessionStore: TrafficRuleSessionStoreStub(),
            trafficRuleStore: trafficRuleStore
        )

        #expect(service.replacedDocuments.count == 1)
        #expect(service.replacedDocuments.last?.rules.map(\.id) == [
            firstUnifiedRule.id,
            migratedRule.id,
            lastUnifiedRule.id
        ])
        viewModel.syncAppliedRules()
        viewModel.syncBreakpointRules()
        #expect(service.replacedDocuments.count == 1)

        viewModel.updateRule(
            key: initialRule.key,
            body: "fresh",
            status: 201,
            headers: ["X-Source": "legacy-editor"],
            isEnabled: false
        )
        #expect(service.replacedDocuments.count == 2)
        #expect(service.incrementalRuleUpdateCount == 0)

        let updatedDocument = try #require(service.replacedDocuments.last)
        #expect(updatedDocument.rules.map(\.id) == [
            firstUnifiedRule.id,
            migratedRule.id,
            lastUnifiedRule.id
        ])
        let updatedRule = try #require(updatedDocument.rules.first { $0.id == migratedRule.id })
        #expect(updatedRule.priority == 1)
        #expect(updatedRule.isEnabled == false)
        if case .mock(let action) = updatedRule.actions.first {
            #expect(action.status == 201)
            #expect(action.headers == ["X-Source": "legacy-editor"])
            #expect(action.body == "fresh")
        } else {
            Issue.record("Expected the legacy Map Local mutation to replace the migrated mock")
        }

        viewModel.syncAppliedRules()
        #expect(service.replacedDocuments.count == 2)

        viewModel.reapplyStoredRules()
        #expect(service.replacedDocuments.count == 3)
    }
}

private final class TrafficRuleProxyServiceSpy: ProxyServiceProtocol {
    private let flows = CurrentValueSubject<[String: MitmFlow], Never>([:])
    private let flowEvents = PassthroughSubject<MitmFlow, Never>()
    private let running = CurrentValueSubject<Bool, Never>(false)

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { flows.eraseToAnyPublisher() }
    var flowEventsPublisher: AnyPublisher<MitmFlow, Never> { flowEvents.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { running.eraseToAnyPublisher() }
    var onLog: ((String) -> Void)?
    var replacedDocuments: [TrafficRuleDocument] = []
    var incrementalRuleUpdateCount = 0
    var stopCount = 0
    var startGate: ProxyServiceStartGate?
    func emit(_ flow: MitmFlow) { flowEvents.send(flow) }
    func emitRunning(_ value: Bool) { running.send(value) }

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws { await startGate?.wait() }
    func stopProxy() { stopCount += 1 }
    func clearFlows() {}
    func mockResponse(for flowID: String, body: String) {}
    func mockRule(_ rule: MapRule) { incrementalRuleUpdateCount += 1 }
    func deleteRule(forKey key: String) { incrementalRuleUpdateCount += 1 }
    func replaceRules(_ document: TrafficRuleDocument) { replacedDocuments.append(document) }
    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {}
    func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?) {}
    func applyTrafficProfile(_ profile: TrafficProfile) {}
    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String]) {}
    func updateBreakpointRule(_ rule: FlowBreakpointRule) { incrementalRuleUpdateCount += 1 }
    func deleteBreakpointRule(forKey key: String) { incrementalRuleUpdateCount += 1 }
    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {}
}

private final class TrafficRuleMapStoreStub: MapRuleStoreProtocol {
    private var rules: [MapRule]

    init(rules: [MapRule]) {
        self.rules = rules
    }

    func loadRules() -> [MapRule] { rules }
    func save(rules: [MapRule]) { self.rules = rules }
}

private final class TrafficRuleBreakpointStoreStub: BreakpointStoreProtocol {
    func loadBreakpoints() -> [FlowBreakpointRule] { [] }
    func save(breakpoints: [FlowBreakpointRule]) {}
}

private actor TrafficRuleSessionStoreStub: SessionStoreProtocol {
    static let schemaVersion = 1

    enum StubError: Error {
        case unsupported
    }

    func createSession(name: String, at date: Date) throws -> CaptureSession { throw StubError.unsupported }
    func sessions() throws -> [CaptureSession] { [] }
    func session(id: UUID) throws -> CaptureSession? { nil }
    func closeSession(id: UUID, at date: Date) throws {}
    func deleteSession(id: UUID) throws {}
    func upsert(
        flow: sending MitmFlow,
        in sessionID: UUID
    ) throws -> SessionFlowUpsertSummary { .empty }
    func flow(id: String, in sessionID: UUID) throws -> CaptureSessionFlow? { nil }
    func page(
        in sessionID: UUID,
        after cursor: CaptureSessionPageCursor?,
        limit: Int
    ) throws -> CaptureSessionPage {
        throw StubError.unsupported
    }
    func setMetadata(
        flowID: String,
        sessionID: UUID,
        note: String?,
        isBookmarked: Bool
    ) throws {}
    func applyRetentionPolicy(_ policy: CaptureSessionRetentionPolicy) throws -> [UUID] { [] }
}

private actor ProxyServiceStartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false
    private var released = false
    func wait() async {
        hasStarted = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
