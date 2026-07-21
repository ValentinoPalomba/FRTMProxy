import Testing
@testable import FRTMProxy

@Suite("Legacy traffic rule adapter")
struct LegacyTrafficRuleAdapterTests {
    @Test("Map Local diventa una mock action deterministica")
    func mapLocal() {
        let rule = MapRule(key: "api.example.com/users", host: "api.example.com", path: "/users", body: "{}", status: 201, headers: [:])
        let first = LegacyTrafficRuleAdapter.document(mapRules: [rule], breakpoints: [], scripts: [])
        let second = LegacyTrafficRuleAdapter.document(mapRules: [rule], breakpoints: [], scripts: [])
        #expect(first == second)
        #expect(first.rules.first?.matcher.host?.value == "api.example.com")
        if case .mock(let action) = first.rules.first?.actions.first {
            #expect(action.status == 201)
        } else {
            Issue.record("Expected a mock action")
        }
    }
}
