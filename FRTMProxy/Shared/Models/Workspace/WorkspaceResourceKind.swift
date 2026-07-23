import Foundation

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
