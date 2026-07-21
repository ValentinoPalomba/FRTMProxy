import Foundation

extension TrafficRuleAction {
    var displayName: String {
        switch self {
        case .mock: "Mock Response"
        case .mapRemote: "Map Remote"
        case .rewriteRequest: "Rewrite Request"
        case .rewriteResponse: "Rewrite Response"
        case .block: "Block"
        case .delay: "Delay"
        case .breakpoint: "Breakpoint"
        case .script: "Script"
        }
    }

    var systemImage: String {
        switch self {
        case .mock: "shippingbox"
        case .mapRemote: "arrow.triangle.swap"
        case .rewriteRequest: "arrow.up.doc"
        case .rewriteResponse: "arrow.down.doc"
        case .block: "nosign"
        case .delay: "clock"
        case .breakpoint: "pause.circle"
        case .script: "curlybraces"
        }
    }
}

extension TrafficRuleMatcher {
    var compactSummary: String {
        let parts: [String] = [method, scheme, host, path].compactMap { pattern -> String? in
            guard let pattern, !pattern.value.isEmpty else { return nil }
            return pattern.value
        }
        return parts.isEmpty ? "All traffic" : parts.joined(separator: " · ")
    }
}
