import Foundation
import Observation

@MainActor
@Observable
final class UnifiedTrafficRuleDraft {
    struct HeaderMatcher: Identifiable, Equatable {
        let id: UUID
        var name: String
        var value: TrafficRuleTextPattern

        init(id: UUID = UUID(), name: String, value: TrafficRuleTextPattern) {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    var rule: TrafficRule
    var headerMatchers: [HeaderMatcher]

    init(rule: TrafficRule) {
        self.rule = rule
        headerMatchers = rule.matcher.headers.map {
            HeaderMatcher(name: $0.name, value: $0.value)
        }
    }

    var validationErrors: [String] {
        materializedRule().matcher.validationErrors
    }

    func materializedRule() -> TrafficRule {
        var result = rule
        result.schemaVersion = TrafficRule.currentSchemaVersion
        result.matcher.headers = headerMatchers
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { .init(name: $0.name, value: $0.value) }
        return result
    }

    func addHeaderMatcher() {
        headerMatchers.append(.init(name: "", value: .init(value: "")))
    }

    func removeHeaderMatcher(id: HeaderMatcher.ID) {
        headerMatchers.removeAll { $0.id == id }
    }

    func upsertAction(_ action: TrafficRuleAction) {
        if let index = rule.actions.firstIndex(where: { $0.id == action.id }) {
            rule.actions[index] = action
        } else {
            rule.actions.append(action)
        }
    }

    func removeAction(id: TrafficRuleAction.ID) {
        rule.actions.removeAll { $0.id == id }
    }

    func moveAction(id: TrafficRuleAction.ID, direction: UnifiedTrafficRulesViewModel.MoveDirection) {
        guard let index = rule.actions.firstIndex(where: { $0.id == id }) else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard rule.actions.indices.contains(destination) else { return }
        rule.actions.swapAt(index, destination)
    }
}
