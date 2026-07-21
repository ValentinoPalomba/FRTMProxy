import CryptoKit
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
            id: stableUUID("map:\(rule.key)"),
            name: "Map Local · \(rule.host)\(rule.path)",
            isEnabled: rule.isEnabled,
            priority: priority,
            matcher: matcher,
            actions: [.mock(.init(id: stableUUID("map-action:\(rule.key)"), status: rule.status, headers: rule.headers, body: rule.body))]
        )
    }

    private static func breakpoint(_ rule: FlowBreakpointRule, priority: Int) -> TrafficRule {
        TrafficRule(
            id: stableUUID("breakpoint:\(rule.key)"),
            name: "Breakpoint · \(rule.host)\(rule.path)",
            isEnabled: rule.isEnabled,
            priority: priority,
            matcher: matcher(host: rule.host, path: rule.path, scheme: rule.scheme),
            actions: [.breakpoint(.init(
                id: stableUUID("breakpoint-action:\(rule.key)"),
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

    private static func stableUUID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
