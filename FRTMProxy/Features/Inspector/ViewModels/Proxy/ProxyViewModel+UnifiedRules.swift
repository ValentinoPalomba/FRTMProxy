import Foundation

extension ProxyViewModel {
    func loadUnifiedTrafficRules() {
        do {
            trafficRuleDocument = TrafficRuleDocument(rules: try trafficRuleStore.loadRules())
        } catch {
            appendLog("[RULES] unable to load unified rules: \(error.localizedDescription)\n")
        }
        syncUnifiedTrafficRules()
    }

    func saveUnifiedTrafficRules(_ document: TrafficRuleDocument) {
        do {
            try trafficRuleStore.save(rules: document.rules)
            trafficRuleDocument = document
            syncUnifiedTrafficRules()
        } catch {
            appendLog("[RULES] unable to save unified rules: \(error.localizedDescription)\n")
            onToast?("Unable to save traffic rules", .error)
        }
    }

    func syncUnifiedTrafficRules() {
        let legacyDocument = LegacyTrafficRuleAdapter.document(
            mapRules: Array(appliedRules.values),
            breakpoints: Array(appliedBreakpointRules.values),
            scripts: scripts
        )
        let unifiedIDs = Set(trafficRuleDocument.rules.map(\.id))
        let legacyRules = legacyDocument.rules.filter { !unifiedIDs.contains($0.id) }
        service.replaceRules(TrafficRuleDocument(rules: trafficRuleDocument.rules + legacyRules))
    }
}
