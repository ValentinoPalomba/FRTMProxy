import Foundation
import Testing
@testable import FRTMProxy

@Suite("Traffic rule domain contract")
struct TrafficRuleModelTests {
    @Test("Codable preserves schema, priority, action order, and action identity")
    func codableRoundTrip() throws {
        let firstID = UUID()
        let secondID = UUID()
        let rule = TrafficRule(
            name: "Rewrite then pause",
            priority: 42,
            matcher: .init(host: .init(value: "*.example.com", mode: .wildcard, isCaseSensitive: false)),
            actions: [
                .rewriteRequest(.init(id: firstID, method: "POST", url: nil, headers: [:], body: nil)),
                .breakpoint(.init(id: secondID, request: true, response: false))
            ]
        )

        let decoded = try JSONDecoder().decode(TrafficRule.self, from: JSONEncoder().encode(rule))

        #expect(decoded == rule)
        #expect(decoded.schemaVersion == TrafficRule.currentSchemaVersion)
        #expect(decoded.priority == 42)
        #expect(decoded.actions.map(\.id) == [firstID, secondID])
    }

    @Test("Invalid regex reports validation and safely fails matching")
    func invalidRegexDoesNotCrash() {
        let matcher = TrafficRuleMatcher(
            host: .init(value: "[", mode: .regularExpression)
        )
        let context = TrafficRuleMatchContext(
            scheme: "https",
            host: "api.example.com",
            path: "/users",
            method: "GET",
            url: "https://api.example.com/users"
        )

        #expect(!matcher.validationErrors.isEmpty)
        #expect(!matcher.matches(context))
    }

    @Test("Matching uses canonical query, body, method, and case-insensitive header names")
    func canonicalMatching() {
        let matcher = TrafficRuleMatcher(
            host: .init(value: "API.EXAMPLE.COM", isCaseSensitive: false),
            path: .init(value: "/v1/*", mode: .wildcard),
            method: .init(value: "POST", isCaseSensitive: false),
            query: .init(value: "a=1&b=2"),
            body: .init(value: #"{"a":1,"b":2}"#),
            headers: [.init(name: "X-Environment", value: .init(value: "staging"))]
        )
        let context = TrafficRuleMatchContext(
            scheme: "https",
            host: "api.example.com",
            path: "/v1/users",
            method: " post ",
            url: "https://api.example.com/v1/users?b=2&a=1",
            headers: ["content-TYPE": "application/json", "x-environment": "staging"],
            body: #"{"b":2,"a":1}"#
        )

        #expect(matcher.matches(context))
    }
}
