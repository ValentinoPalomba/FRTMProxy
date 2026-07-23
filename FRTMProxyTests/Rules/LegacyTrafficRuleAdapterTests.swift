import Combine
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Legacy traffic rule adapter")
struct LegacyTrafficRuleAdapterTests {
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

    @Test("Legacy mutations replace stale migrated content without changing unified order")
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

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws {}
    func stopProxy() {}
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
