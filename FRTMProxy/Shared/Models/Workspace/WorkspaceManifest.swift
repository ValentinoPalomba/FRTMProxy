import Foundation

enum WorkspaceFormat {
    static let currentSchemaVersion = 1
    static let manifestFilename = "frtm-workspace.json"
}

struct WorkspaceManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    let identifier: String
    var displayName: String
    var summary: String?
    var resources: WorkspaceResources

    init(
        schemaVersion: Int = WorkspaceFormat.currentSchemaVersion,
        identifier: String,
        displayName: String,
        summary: String? = nil,
        resources: WorkspaceResources = WorkspaceResources()
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.displayName = displayName
        self.summary = summary
        self.resources = resources
    }
}

struct WorkspaceResources: Codable, Equatable, Sendable {
    var rules: [WorkspaceResourceReference]
    var scripts: [WorkspaceResourceReference]
    var breakpoints: [WorkspaceResourceReference]
    var profiles: [WorkspaceResourceReference]
    var sessions: [WorkspaceResourceReference]
    var policies: [WorkspaceResourceReference]

    init(
        rules: [WorkspaceResourceReference] = [],
        scripts: [WorkspaceResourceReference] = [],
        breakpoints: [WorkspaceResourceReference] = [],
        profiles: [WorkspaceResourceReference] = [],
        sessions: [WorkspaceResourceReference] = [],
        policies: [WorkspaceResourceReference] = []
    ) {
        self.rules = rules
        self.scripts = scripts
        self.breakpoints = breakpoints
        self.profiles = profiles
        self.sessions = sessions
        self.policies = policies
    }

    var count: Int {
        rules.count + scripts.count + breakpoints.count + profiles.count + sessions.count + policies.count
    }
}

struct WorkspaceResourceReference: Codable, Equatable, Hashable, Sendable {
    let identifier: String
    let path: String

    init(identifier: String, path: String) {
        self.identifier = identifier
        self.path = path
    }
}

enum WorkspaceResourceKind: String, CaseIterable, Sendable {
    case rule = "rules"
    case script = "scripts"
    case breakpoint = "breakpoints"
    case profile = "profiles"
    case session = "sessions"
    case policy = "policies"

    var allowedPathExtensions: Set<String> {
        switch self {
        case .rule, .breakpoint, .profile, .policy:
            ["json"]
        case .script:
            ["js", "json"]
        case .session:
            ["har", "json"]
        }
    }
}
