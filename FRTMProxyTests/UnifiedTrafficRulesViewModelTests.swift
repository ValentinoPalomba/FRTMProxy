import Foundation
import Testing
@testable import FRTMProxy

@MainActor
@Suite("Unified traffic rules UI state")
struct UnifiedTrafficRulesViewModelTests {
    @Test("Reordering normalizes priorities while preserving rule identity")
    func reorderRules() {
        let first = makeRule(name: "First", priority: 10)
        let second = makeRule(name: "Second", priority: 20)
        let model = UnifiedTrafficRulesViewModel(document: .init(rules: [first, second]))

        model.move(ruleID: second.id, direction: .up)

        #expect(model.orderedRules.map(\.id) == [second.id, first.id])
        #expect(model.orderedRules.map(\.priority) == [0, 1])
    }

    @Test("Editing an action preserves its stable position and identity")
    func actionIdentity() {
        let action = UnifiedTrafficRuleActionFormModel.defaultAction(for: .mock)
        let draft = UnifiedTrafficRuleDraft(rule: TrafficRule(
            name: "Mock",
            matcher: .init(),
            actions: [action]
        ))
        let updated = TrafficRuleAction.mock(.init(
            id: action.id,
            status: 201,
            headers: [:],
            body: "created"
        ))

        draft.upsertAction(updated)

        #expect(draft.rule.actions.count == 1)
        #expect(draft.rule.actions.first?.id == action.id)
    }

    @Test("Materializing a draft uses editable header identities only inside the UI")
    func materializeHeaders() {
        let draft = UnifiedTrafficRuleDraft(rule: makeRule(name: "Headers", priority: 0))
        draft.addHeaderMatcher()
        draft.headerMatchers[0].name = "X-Environment"
        draft.headerMatchers[0].value = .init(value: "staging", isCaseSensitive: false)

        let rule = draft.materializedRule()

        #expect(rule.matcher.headers.count == 1)
        #expect(rule.matcher.headers[0].name == "X-Environment")
        #expect(rule.matcher.headers[0].value.value == "staging")
    }

    private func makeRule(name: String, priority: Int) -> TrafficRule {
        TrafficRule(
            name: name,
            priority: priority,
            matcher: .init(host: .init(value: "example.com")),
            actions: [.delay(.init(id: UUID(), requestMilliseconds: 0, responseMilliseconds: 1))]
        )
    }
}
