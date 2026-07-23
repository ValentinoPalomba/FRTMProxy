import Foundation

enum LegacyTrafficRuleAdapter {
    static func document(
        mapRules: [MapRule],
        breakpoints: [FlowBreakpointRule],
        scripts: [ScriptRule]
    ) -> TrafficRuleDocument {
        var priority = 0
        var converted: [TrafficRule] = []

        for rule in mapRules.sorted(by: { $0.key < $1.key }) {
            converted.append(mapRule(rule, priority: priority))
            priority += 1
        }
        for rule in breakpoints.sorted(by: { $0.key < $1.key }) {
            converted.append(breakpoint(rule, priority: priority))
            priority += 1
        }
        for rule in scripts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            converted.append(script(rule, priority: priority))
            priority += 1
        }
        return TrafficRuleDocument(rules: converted)
    }

    private static func mapRule(_ rule: MapRule, priority: Int) -> TrafficRule {
        var matcher = matcher(host: rule.host, path: rule.path, scheme: rule.scheme)
        if let request = rule.request {
            let contentType = request.headers.first(where: { $0.key.caseInsensitiveCompare("content-type") == .orderedSame })?.value
            matcher.method = .init(value: TrafficRuleCanonicalizer.method(request.method), isCaseSensitive: false)
            matcher.query = .init(value: TrafficRuleCanonicalizer.query(from: request.url))
            matcher.body = .init(value: TrafficRuleCanonicalizer.body(request.body, contentType: contentType))
        }
        return TrafficRule(
            id: TrafficRuleCanonicalizer.legacyIdentifier(for: "map:\(rule.key)"),
            name: "Map Local · \(rule.host)\(rule.path)",
            isEnabled: rule.isEnabled,
            priority: priority,
            matcher: matcher,
            actions: [.mock(.init(
                id: TrafficRuleCanonicalizer.legacyIdentifier(for: "map-action:\(rule.key)"),
                status: rule.status,
                headers: rule.headers,
                body: rule.body
            ))]
        )
    }

    private static func breakpoint(_ rule: FlowBreakpointRule, priority: Int) -> TrafficRule {
        TrafficRule(
            id: TrafficRuleCanonicalizer.legacyIdentifier(for: "breakpoint:\(rule.key)"),
            name: "Breakpoint · \(rule.host)\(rule.path)",
            isEnabled: rule.isEnabled,
            priority: priority,
            matcher: matcher(host: rule.host, path: rule.path, scheme: rule.scheme),
            actions: [.breakpoint(.init(
                id: TrafficRuleCanonicalizer.legacyIdentifier(for: "breakpoint-action:\(rule.key)"),
                request: rule.interceptRequest,
                response: rule.interceptResponse
            ))]
        )
    }

    private static func script(_ rule: ScriptRule, priority: Int) -> TrafficRule {
        TrafficRule(
            id: rule.id,
            name: rule.name.isEmpty ? "Response script" : rule.name,
            isEnabled: rule.isEnabled,
            priority: priority,
            matcher: matcher(host: rule.host, path: rule.path, scheme: nil),
            actions: [.script(.init(id: rule.id, source: rule.code, responseOnly: true))]
        )
    }

    private static func matcher(host: String, path: String, scheme: String?) -> TrafficRuleMatcher {
        TrafficRuleMatcher(
            scheme: scheme.flatMap { $0.isEmpty ? nil : .init(value: $0, isCaseSensitive: false) },
            host: host.isEmpty ? nil : pattern(host, caseSensitive: false),
            path: path.isEmpty ? nil : pattern(path, caseSensitive: true)
        )
    }

    private static func pattern(_ value: String, caseSensitive: Bool) -> TrafficRuleTextPattern {
        let mode: TrafficRuleTextPattern.Mode = value.contains("*") || value.contains("?") ? .wildcard : .exact
        return .init(value: value, mode: mode, isCaseSensitive: caseSensitive)
    }
}
