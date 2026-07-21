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
        self.document = document
        selectedRuleID = nil
        selectedRuleID = orderedRules.first?.id
    }

    var orderedRules: [TrafficRule] {
        document.rules.sorted {
            if $0.priority == $1.priority {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.priority < $1.priority
        }
    }

    func upsert(_ rule: TrafficRule) {
        if let index = document.rules.firstIndex(where: { $0.id == rule.id }) {
            document.rules[index] = rule
        } else {
            document.rules.append(rule)
        }
        selectedRuleID = rule.id
        normalizePriorities(preservingOrder: orderedRules)
    }

    func delete(ruleID: TrafficRule.ID) {
        document.rules.removeAll { $0.id == ruleID }
        normalizePriorities(preservingOrder: orderedRules)
        if selectedRuleID == ruleID {
            selectedRuleID = orderedRules.first?.id
        }
    }

    func setEnabled(_ isEnabled: Bool, ruleID: TrafficRule.ID) {
        guard let index = document.rules.firstIndex(where: { $0.id == ruleID }) else { return }
        document.rules[index].isEnabled = isEnabled
    }

    func move(ruleID: TrafficRule.ID, direction: MoveDirection) {
        var rules = orderedRules
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard rules.indices.contains(destination) else { return }
        rules.swapAt(index, destination)
        normalizePriorities(preservingOrder: rules)
    }

    func canMove(ruleID: TrafficRule.ID, direction: MoveDirection) -> Bool {
        guard let index = orderedRules.firstIndex(where: { $0.id == ruleID }) else { return false }
        switch direction {
        case .up: return index > orderedRules.startIndex
        case .down: return index < orderedRules.index(before: orderedRules.endIndex)
        }
    }

    func preparedDocument() -> TrafficRuleDocument {
        var result = document
        result.schemaVersion = TrafficRuleDocument.currentSchemaVersion
        for index in result.rules.indices {
            result.rules[index].schemaVersion = TrafficRule.currentSchemaVersion
        }
        return result
    }

    private func normalizePriorities(preservingOrder rules: [TrafficRule]) {
        var normalized = rules
        for index in normalized.indices {
            normalized[index].priority = index
        }
        document.rules = normalized
    }
}
