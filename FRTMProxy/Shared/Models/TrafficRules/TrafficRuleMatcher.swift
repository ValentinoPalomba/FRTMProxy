import Foundation

struct TrafficRuleMatcher: Codable, Hashable, Sendable {
    struct Header: Codable, Hashable, Sendable, Identifiable {
        var name: String
        var value: TrafficRuleTextPattern
        var id: String { name.lowercased() }
    }

    var scheme: TrafficRuleTextPattern?
    var host: TrafficRuleTextPattern?
    var path: TrafficRuleTextPattern?
    var method: TrafficRuleTextPattern?
    var query: TrafficRuleTextPattern?
    var body: TrafficRuleTextPattern?
    var headers: [Header]

    init(
        scheme: TrafficRuleTextPattern? = nil,
        host: TrafficRuleTextPattern? = nil,
        path: TrafficRuleTextPattern? = nil,
        method: TrafficRuleTextPattern? = nil,
        query: TrafficRuleTextPattern? = nil,
        body: TrafficRuleTextPattern? = nil,
        headers: [Header] = []
    ) {
        self.scheme = scheme
        self.host = host
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.headers = headers
    }

    var validationErrors: [String] {
        let fields: [(String, TrafficRuleTextPattern?)] = [
            ("scheme", scheme), ("host", host), ("path", path), ("method", method),
            ("query", query), ("body", body)
        ]
        var errors = fields.compactMap { name, pattern in
            pattern?.validationError.map { "\(name): \($0)" }
        }
        errors += headers.compactMap { header in
            header.value.validationError.map { "header \(header.name): \($0)" }
        }
        return errors
    }

    func matches(_ context: TrafficRuleMatchContext) -> Bool {
        guard validationErrors.isEmpty else { return false }
        guard scheme?.matches(context.scheme) ?? true,
              host?.matches(context.host) ?? true,
              path?.matches(context.path) ?? true,
              method?.matches(TrafficRuleCanonicalizer.method(context.method)) ?? true,
              query?.matches(TrafficRuleCanonicalizer.query(from: context.url)) ?? true else {
            return false
        }

        let contentType = context.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
        guard body?.matches(TrafficRuleCanonicalizer.body(context.body, contentType: contentType)) ?? true else {
            return false
        }
        return headers.allSatisfy { expected in
            guard let actual = context.headers.first(where: {
                $0.key.caseInsensitiveCompare(expected.name) == .orderedSame
            })?.value else { return false }
            return expected.value.matches(actual)
        }
    }
}
