import Foundation

extension TrafficRuleAction {
    var displayName: String {
        switch self {
        case .mock: String(localized: "Mock Response", bundle: AppLocalization.bundle)
        case .mapRemote: String(localized: "Map Remote", bundle: AppLocalization.bundle)
        case .rewriteRequest: String(localized: "Rewrite Request", bundle: AppLocalization.bundle)
        case .rewriteResponse: String(localized: "Rewrite Response", bundle: AppLocalization.bundle)
        case .block: String(localized: "Block", bundle: AppLocalization.bundle)
        case .delay: String(localized: "Delay", bundle: AppLocalization.bundle)
        case .breakpoint: String(localized: "Breakpoint", bundle: AppLocalization.bundle)
        case .script: String(localized: "Script", bundle: AppLocalization.bundle)
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
        return parts.isEmpty ? String(localized: "All traffic", bundle: AppLocalization.bundle) : parts.joined(separator: " · ")
    }
}
