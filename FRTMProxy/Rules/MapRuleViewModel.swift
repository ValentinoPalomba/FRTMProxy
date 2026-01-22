import Foundation
import Combine

final class MapRuleViewModel: ObservableObject {
    @Published var rules: [MapRule] = []
    @Published var selection: MapRule?

    func load(_ rules: [MapRule]) {
        self.rules = rules
        if let selection, let matched = rules.first(where: { $0.key == selection.key }) {
            select(matched)
        } else if let first = rules.first {
            select(first)
        } else {
            selection = nil
        }
    }

    func select(_ rule: MapRule) {
        selection = rule
    }

    func update(rule: MapRule) {
        if let index = rules.firstIndex(where: { $0.key == rule.key }) {
            rules[index] = rule
        }
        if selection?.key == rule.key {
            selection = rule
        }
    }

    func removeRule(key: String) {
        rules.removeAll { $0.key == key }
        if selection?.key == key {
            selection = rules.first
        }
    }
}
