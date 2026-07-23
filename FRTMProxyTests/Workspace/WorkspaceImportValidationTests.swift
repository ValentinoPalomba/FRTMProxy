import Combine
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace import validation")
struct WorkspaceImportValidationTests {
    @Test("Traversal, absolute, Windows, and wrong-root paths are rejected", arguments: [
        "rules/../secrets.json",
        "../rules/secret.json",
        "/tmp/rule.json",
        "C:\\temp\\rule.json",
        "rules\\..\\secret.json",
        "scripts/rule.json"
    ])
    func rejectsUnsafePaths(path: String) {
        let manifest = WorkspaceManifest(
            identifier: "workspace",
            displayName: "Workspace",
            resources: WorkspaceResources(rules: [.init(identifier: "rule", path: path)])
        )

        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceImportValidator.validate(manifest)
        }
    }

    @Test("Resolution remains inside the workspace and rejects symlink escapes")
    func rejectsSymlinkEscape() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workspace = temporaryRoot.appending(path: "workspace", directoryHint: .isDirectory)
        let rules = workspace.appending(path: "rules", directoryHint: .isDirectory)
        let outside = temporaryRoot.appending(path: "outside", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rules, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let link = rules.appending(path: "linked.json")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside.appending(path: "secret.json"))
        let reference = WorkspaceResourceReference(identifier: "linked", path: "rules/linked.json")

        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceImportValidator.resolve(reference, kind: .rule, inside: workspace)
        }
    }

    @Test("Valid resource paths resolve inside the workspace")
    func resolvesValidPath() throws {
        let root = URL(filePath: "/tmp/FRTMProxyWorkspace", directoryHint: .isDirectory)
        let reference = WorkspaceResourceReference(identifier: "rule", path: "rules/example.json")

        let resolved = try WorkspaceImportValidator.resolve(reference, kind: .rule, inside: root)

        #expect(resolved.path == "/tmp/FRTMProxyWorkspace/rules/example.json")
    }

    @Test("Every supported resource decodes before an import plan is returned")
    func rejectsEntirePlanWhenOneResourceIsInvalid() throws {
        let ruleReference = WorkspaceResourceReference(
            identifier: "rules",
            path: "rules/rules.json"
        )
        let breakpointReference = WorkspaceResourceReference(
            identifier: "breakpoints",
            path: "breakpoints/breakpoints.json"
        )
        let manifest = WorkspaceManifest(
            identifier: "workspace",
            displayName: "Workspace",
            resources: WorkspaceResources(
                rules: [ruleReference],
                breakpoints: [breakpointReference]
            )
        )
        let validRules = try JSONEncoder().encode(TrafficRuleDocument(rules: []))
        let bundle = WorkspaceBundle(
            manifest: manifest,
            resources: [
                .init(kind: .rule, reference: ruleReference, data: validRules),
                .init(kind: .breakpoint, reference: breakpointReference, data: Data("{".utf8))
            ]
        )

        #expect(throws: WorkspaceImportPlanError.self) {
            try WorkspaceImportPlan.prepare(bundle)
        }
    }

    @Test("Duplicate breakpoint keys are validation errors")
    func rejectsDuplicateBreakpointKeys() throws {
        let reference = WorkspaceResourceReference(
            identifier: "breakpoints",
            path: "breakpoints/breakpoints.json"
        )
        let rule = FlowBreakpointRule(
            key: "api.example.com/users",
            host: "api.example.com",
            path: "/users",
            scheme: "https",
            interceptRequest: true,
            interceptResponse: false
        )
        let bundle = WorkspaceBundle(
            manifest: WorkspaceManifest(
                identifier: "workspace",
                displayName: "Workspace",
                resources: WorkspaceResources(breakpoints: [reference])
            ),
            resources: [
                .init(
                    kind: .breakpoint,
                    reference: reference,
                    data: try JSONEncoder().encode([rule, rule])
                )
            ]
        )

        #expect(throws: WorkspaceImportPlanError.duplicateBreakpointKey(rule.key)) {
            try WorkspaceImportPlan.prepare(bundle)
        }
    }

    @Test("JavaScript resources are valid but explicitly skipped")
    func classifiesJavaScriptAsSkipped() throws {
        let reference = WorkspaceResourceReference(
            identifier: "transform",
            path: "scripts/transform.js"
        )
        let bundle = WorkspaceBundle(
            manifest: WorkspaceManifest(
                identifier: "workspace",
                displayName: "Workspace",
                resources: WorkspaceResources(scripts: [reference])
            ),
            resources: [
                .init(
                    kind: .script,
                    reference: reference,
                    data: Data("function transform(flow) { return flow; }".utf8)
                )
            ]
        )

        let plan = try WorkspaceImportPlan.prepare(bundle)

        #expect(plan.scripts == nil)
        #expect(plan.resourcesToApply.isEmpty)
        #expect(plan.skippedResources.count == 1)
        #expect(plan.skippedResources[0].reference == reference)
    }

    @Test("Applying a prepared workspace replaces effective rules once")
    func appliesWithOneEffectiveRuleSync() throws {
        let reference = WorkspaceResourceReference(
            identifier: "rules",
            path: "rules/rules.json"
        )
        let document = TrafficRuleDocument(rules: [])
        let plan = try WorkspaceImportPlan.prepare(
            WorkspaceBundle(
                manifest: WorkspaceManifest(
                    identifier: "workspace",
                    displayName: "Workspace",
                    resources: WorkspaceResources(rules: [reference])
                ),
                resources: [
                    .init(
                        kind: .rule,
                        reference: reference,
                        data: try JSONEncoder().encode(document)
                    )
                ]
            )
        )
        let service = WorkspaceProxyServiceSpy()
        let viewModel = ProxyViewModel(
            service: service,
            ruleStore: WorkspaceMapRuleStoreStub(),
            collectionStore: MapCollectionStore(filename: "workspace-\(UUID().uuidString).json"),
            breakpointStore: WorkspaceBreakpointStoreStub(),
            scriptStore: ScriptStore(filename: "workspace-\(UUID().uuidString).json"),
            sessionStore: WorkspaceSessionStoreStub(),
            trafficRuleStore: WorkspaceTrafficRuleStoreStub()
        )
        let syncCountBeforeImport = service.replacedDocuments.count

        let result = try viewModel.applyWorkspaceBundle(plan)

        #expect(service.replacedDocuments.count == syncCountBeforeImport + 1)
        #expect(result.appliedResources.count == 1)
        #expect(result.skippedResources.isEmpty)
    }
}

private final class WorkspaceProxyServiceSpy: ProxyServiceProtocol {
    private let flows = CurrentValueSubject<[String: MitmFlow], Never>([:])
    private let flowEvents = PassthroughSubject<MitmFlow, Never>()
    private let running = CurrentValueSubject<Bool, Never>(false)

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { flows.eraseToAnyPublisher() }
    var flowEventsPublisher: AnyPublisher<MitmFlow, Never> { flowEvents.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { running.eraseToAnyPublisher() }
    var onLog: ((String) -> Void)?
    var replacedDocuments: [TrafficRuleDocument] = []

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws {}
    func stopProxy() {}
    func clearFlows() {}
    func mockResponse(for flowID: String, body: String) {}
    func mockRule(_ rule: MapRule) {}
    func deleteRule(forKey key: String) {}
    func replaceRules(_ document: TrafficRuleDocument) { replacedDocuments.append(document) }
    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {}
    func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?) {}
    func applyTrafficProfile(_ profile: TrafficProfile) {}
    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String]) {}
    func updateBreakpointRule(_ rule: FlowBreakpointRule) {}
    func deleteBreakpointRule(forKey key: String) {}
    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {}
}

private final class WorkspaceMapRuleStoreStub: MapRuleStoreProtocol {
    func loadRules() -> [MapRule] { [] }
    func save(rules: [MapRule]) {}
}

private final class WorkspaceBreakpointStoreStub: BreakpointStoreProtocol {
    func loadBreakpoints() -> [FlowBreakpointRule] { [] }
    func save(breakpoints: [FlowBreakpointRule]) {}
}

private final class WorkspaceTrafficRuleStoreStub: TrafficRuleStoreProtocol {
    private var rules: [TrafficRule] = []

    func loadRules() throws -> [TrafficRule] { rules }
    func save(rules: [TrafficRule]) throws { self.rules = rules }
}

private actor WorkspaceSessionStoreStub: SessionStoreProtocol {
    static let schemaVersion = 1

    enum StubError: Error {
        case unsupported
    }

    func createSession(name: String, at date: Date) throws -> CaptureSession {
        throw StubError.unsupported
    }

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
