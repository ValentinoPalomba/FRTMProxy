import Foundation

struct WorkspaceResourcePayload: Equatable, Sendable {
    let kind: WorkspaceResourceKind
    let reference: WorkspaceResourceReference
    let data: Data

    init(kind: WorkspaceResourceKind, reference: WorkspaceResourceReference, data: Data) {
        self.kind = kind
        self.reference = reference
        self.data = data
    }
}

struct WorkspaceBundle: Equatable, Sendable {
    let manifest: WorkspaceManifest
    let resources: [WorkspaceResourcePayload]

    init(manifest: WorkspaceManifest, resources: [WorkspaceResourcePayload]) {
        self.manifest = manifest
        self.resources = resources
    }
}

enum WorkspaceImportDisposition: Equatable {
    case apply
    case skip(reason: WorkspaceImportSkipReason)
}

enum WorkspaceImportSkipReason: Equatable {
    case javascriptRequiresManualImport
    case unsupportedResourceType
}

struct WorkspaceImportResource: Identifiable, Equatable {
    let kind: WorkspaceResourceKind
    let reference: WorkspaceResourceReference
    let byteCount: Int
    let disposition: WorkspaceImportDisposition

    var id: String { reference.path }
}

struct WorkspaceImportPlan {
    let bundle: WorkspaceBundle
    let resources: [WorkspaceImportResource]
    let trafficRuleDocument: TrafficRuleDocument?
    let scripts: [ScriptRule]?
    let breakpointRules: [String: FlowBreakpointRule]?

    var resourcesToApply: [WorkspaceImportResource] {
        resources.filter { $0.disposition == .apply }
    }

    var skippedResources: [WorkspaceImportResource] {
        resources.filter {
            if case .skip = $0.disposition {
                return true
            }
            return false
        }
    }

    static func prepare(_ bundle: WorkspaceBundle) throws -> WorkspaceImportPlan {
        try WorkspaceImportValidator.validate(bundle.manifest)

        let expectedEntries = resourceEntries(in: bundle.manifest)
        let expectedByPath = Dictionary(
            uniqueKeysWithValues: expectedEntries.map { ($0.reference.path, $0) }
        )
        var seenPaths: Set<String> = []
        var resources: [WorkspaceImportResource] = []
        var importedRules: [TrafficRule] = []
        var importedScripts: [ScriptRule] = []
        var importedBreakpoints: [String: FlowBreakpointRule] = [:]
        var includesRules = false
        var includesScripts = false
        var includesBreakpoints = false
        let decoder = JSONDecoder()

        for payload in bundle.resources.sorted(by: { $0.reference.path < $1.reference.path }) {
            guard seenPaths.insert(payload.reference.path).inserted else {
                throw WorkspaceImportPlanError.duplicatePayload(payload.reference.path)
            }
            guard let expected = expectedByPath[payload.reference.path],
                  expected.kind == payload.kind,
                  expected.reference == payload.reference else {
                throw WorkspaceImportPlanError.unexpectedPayload(payload.reference.path)
            }

            do {
                switch payload.kind {
                case .rule:
                    let document = try decoder.decode(TrafficRuleDocument.self, from: payload.data)
                    guard document.schemaVersion <= TrafficRuleDocument.currentSchemaVersion else {
                        throw WorkspaceImportPlanError.unsupportedTrafficRuleSchema(
                            path: payload.reference.path,
                            version: document.schemaVersion
                        )
                    }
                    if let unsupportedRule = document.rules.first(where: {
                        $0.schemaVersion > TrafficRule.currentSchemaVersion
                    }) {
                        throw WorkspaceImportPlanError.unsupportedTrafficRuleSchema(
                            path: payload.reference.path,
                            version: unsupportedRule.schemaVersion
                        )
                    }
                    includesRules = true
                    importedRules.append(contentsOf: document.rules)
                    resources.append(importResource(for: payload, disposition: .apply))

                case .script where URL(filePath: payload.reference.path).pathExtension.lowercased() == "js":
                    guard String(data: payload.data, encoding: .utf8) != nil else {
                        throw WorkspaceImportPlanError.invalidUTF8(payload.reference.path)
                    }
                    resources.append(importResource(
                        for: payload,
                        disposition: .skip(reason: .javascriptRequiresManualImport)
                    ))

                case .script:
                    includesScripts = true
                    importedScripts.append(contentsOf: try decoder.decode([ScriptRule].self, from: payload.data))
                    resources.append(importResource(for: payload, disposition: .apply))

                case .breakpoint:
                    includesBreakpoints = true
                    let rules = try decoder.decode([FlowBreakpointRule].self, from: payload.data)
                    for rule in rules {
                        guard importedBreakpoints[rule.key] == nil else {
                            throw WorkspaceImportPlanError.duplicateBreakpointKey(rule.key)
                        }
                        importedBreakpoints[rule.key] = rule
                    }
                    resources.append(importResource(for: payload, disposition: .apply))

                case .profile, .session, .policy:
                    try validateSkippedPayload(payload)
                    resources.append(importResource(
                        for: payload,
                        disposition: .skip(reason: .unsupportedResourceType)
                    ))
                }
            } catch let error as WorkspaceImportPlanError {
                throw error
            } catch {
                throw WorkspaceImportPlanError.invalidResource(
                    path: payload.reference.path,
                    reason: error.localizedDescription
                )
            }
        }

        let missingPaths = Set(expectedByPath.keys).subtracting(seenPaths)
        guard missingPaths.isEmpty else {
            throw WorkspaceImportPlanError.missingPayload(missingPaths.sorted().joined(separator: ", "))
        }

        if let duplicateRuleID = duplicate(in: importedRules.map(\.id)) {
            throw WorkspaceImportPlanError.duplicateTrafficRuleID(duplicateRuleID)
        }
        if let duplicateScriptID = duplicate(in: importedScripts.map(\.id)) {
            throw WorkspaceImportPlanError.duplicateScriptID(duplicateScriptID)
        }

        return WorkspaceImportPlan(
            bundle: bundle,
            resources: resources,
            trafficRuleDocument: includesRules ? TrafficRuleDocument(rules: importedRules) : nil,
            scripts: includesScripts ? importedScripts : nil,
            breakpointRules: includesBreakpoints ? importedBreakpoints : nil
        )
    }

    private static func resourceEntries(
        in manifest: WorkspaceManifest
    ) -> [(kind: WorkspaceResourceKind, reference: WorkspaceResourceReference)] {
        manifest.resources.rules.map { (.rule, $0) }
            + manifest.resources.scripts.map { (.script, $0) }
            + manifest.resources.breakpoints.map { (.breakpoint, $0) }
            + manifest.resources.profiles.map { (.profile, $0) }
            + manifest.resources.sessions.map { (.session, $0) }
            + manifest.resources.policies.map { (.policy, $0) }
    }

    private static func importResource(
        for payload: WorkspaceResourcePayload,
        disposition: WorkspaceImportDisposition
    ) -> WorkspaceImportResource {
        WorkspaceImportResource(
            kind: payload.kind,
            reference: payload.reference,
            byteCount: payload.data.count,
            disposition: disposition
        )
    }

    private static func validateSkippedPayload(_ payload: WorkspaceResourcePayload) throws {
        switch URL(filePath: payload.reference.path).pathExtension.lowercased() {
        case "json", "har":
            do {
                _ = try JSONSerialization.jsonObject(with: payload.data, options: [.fragmentsAllowed])
            } catch {
                throw WorkspaceImportPlanError.invalidResource(
                    path: payload.reference.path,
                    reason: "Invalid JSON."
                )
            }
        default:
            throw WorkspaceImportPlanError.invalidResource(
                path: payload.reference.path,
                reason: "Unsupported content."
            )
        }
    }

    private static func duplicate<Value: Hashable>(in values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }
}

struct WorkspaceImportResult: Equatable {
    let appliedResources: [WorkspaceImportResource]
    let skippedResources: [WorkspaceImportResource]
}

enum WorkspaceImportPlanError: Error, Equatable, LocalizedError {
    case duplicatePayload(String)
    case unexpectedPayload(String)
    case missingPayload(String)
    case invalidResource(path: String, reason: String)
    case invalidUTF8(String)
    case unsupportedTrafficRuleSchema(path: String, version: Int)
    case duplicateTrafficRuleID(UUID)
    case duplicateScriptID(UUID)
    case duplicateBreakpointKey(String)

    var errorDescription: String? {
        switch self {
        case let .duplicatePayload(path):
            "Duplicate workspace payload: \(path)"
        case let .unexpectedPayload(path):
            "Unexpected workspace payload: \(path)"
        case let .missingPayload(path):
            "Missing workspace payload: \(path)"
        case let .invalidResource(path, reason):
            "\(path) could not be imported. \(reason)"
        case let .invalidUTF8(path):
            "JavaScript resource is not UTF-8: \(path)"
        case let .unsupportedTrafficRuleSchema(path, version):
            "\(path) uses unsupported traffic rule schema \(version)."
        case let .duplicateTrafficRuleID(id):
            "Traffic rule ID \(id) appears more than once."
        case let .duplicateScriptID(id):
            "Script ID \(id) appears more than once."
        case let .duplicateBreakpointKey(key):
            "Breakpoint key \(key) appears more than once."
        }
    }
}

struct WorkspaceServiceLimits: Equatable, Sendable {
    static let defaults = WorkspaceServiceLimits()

    let validation: WorkspaceValidationLimits
    let maximumResourceBytes: Int
    let maximumTotalResourceBytes: Int

    init(
        validation: WorkspaceValidationLimits = .defaults,
        maximumResourceBytes: Int = 25 * 1_024 * 1_024,
        maximumTotalResourceBytes: Int = 250 * 1_024 * 1_024
    ) {
        self.validation = validation
        self.maximumResourceBytes = maximumResourceBytes
        self.maximumTotalResourceBytes = maximumTotalResourceBytes
    }

    func validate() throws {
        guard maximumResourceBytes > 0, maximumTotalResourceBytes > 0 else {
            throw WorkspaceServiceError.invalidLimits
        }
        guard maximumResourceBytes <= maximumTotalResourceBytes else {
            throw WorkspaceServiceError.invalidLimits
        }
    }
}
