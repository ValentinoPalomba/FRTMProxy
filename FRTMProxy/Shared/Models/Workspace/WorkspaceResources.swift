import Foundation

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
