import Foundation
import Observation

@MainActor
@Observable
final class UnifiedTrafficRulesViewModel {
    enum MoveDirection: Equatable {
        case up
        case down
    }

    var document: TrafficRuleDocument
    var selectedRuleID: TrafficRule.ID?

    init(document: TrafficRuleDocument) {
        var normalizedDocument = document
        normalizedDocument.rules = Self.normalized(document.rules)
        self.document = normalizedDocument
        selectedRuleID = normalizedDocument.rules.first?.id
    }

    var orderedRules: [TrafficRule] {
        document.rules
    }

    func upsert(_ rule: TrafficRule) {
        if let index = document.rules.firstIndex(where: { $0.id == rule.id }) {
            var updatedRule = rule
            updatedRule.priority = index
            document.rules[index] = updatedRule
        } else {
            var appendedRule = rule
            appendedRule.priority = document.rules.count
            document.rules.append(appendedRule)
        }
        selectedRuleID = rule.id
    }

    func delete(ruleID: TrafficRule.ID) {
        document.rules.removeAll { $0.id == ruleID }
        document.rules = Self.normalized(document.rules, sortByPriority: false)
        if selectedRuleID == ruleID {
            selectedRuleID = document.rules.first?.id
        }
    }

    func setEnabled(_ isEnabled: Bool, ruleID: TrafficRule.ID) {
        guard let index = document.rules.firstIndex(where: { $0.id == ruleID }) else { return }
        document.rules[index].isEnabled = isEnabled
    }

    func move(ruleID: TrafficRule.ID, direction: MoveDirection) {
        guard let index = document.rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard document.rules.indices.contains(destination) else { return }
        document.rules.swapAt(index, destination)
        document.rules = Self.normalized(document.rules, sortByPriority: false)
    }

    func preparedDocument() -> TrafficRuleDocument {
        var result = document
        result.schemaVersion = TrafficRuleDocument.currentSchemaVersion
        result.rules = Self.normalized(result.rules, sortByPriority: false)
        for index in result.rules.indices {
            result.rules[index].schemaVersion = TrafficRule.currentSchemaVersion
        }
        return result
    }

    private static func normalized(
        _ rules: [TrafficRule],
        sortByPriority: Bool = true
    ) -> [TrafficRule] {
        var normalized = sortByPriority ? rules.sorted {
            if $0.priority == $1.priority {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.priority < $1.priority
        } : rules
        for index in normalized.indices {
            normalized[index].priority = index
        }
        return normalized
    }
}
