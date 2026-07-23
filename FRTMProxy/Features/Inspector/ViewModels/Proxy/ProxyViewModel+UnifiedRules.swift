import Foundation

enum TrafficRuleDocumentSaveError: LocalizedError {
    case unsupportedDocumentSchema(Int)
    case unsupportedRuleSchema(ruleName: String, version: Int)
    case duplicateRuleID(UUID)
    case invalidMatcher(ruleName: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case .unsupportedDocumentSchema(let version):
            "Unsupported traffic rule document schema \(version)"
        case let .unsupportedRuleSchema(ruleName, version):
            "Unsupported schema \(version) for rule “\(ruleName)”"
        case .duplicateRuleID(let id):
            "Duplicate traffic rule ID \(id.uuidString)"
        case let .invalidMatcher(ruleName, errors):
            "Invalid matcher for rule “\(ruleName)”: \(errors.joined(separator: ", "))"
        }
    }
}

extension ProxyViewModel {
    func loadUnifiedTrafficRules() {
        do {
            trafficRuleDocument = TrafficRuleDocument(rules: try trafficRuleStore.loadRules())
        } catch {
            appendLog("[RULES] unable to load unified rules: \(error.localizedDescription)\n")
        }
        synchronizeEffectiveTrafficRules(force: true)
    }

    @MainActor
    func saveUnifiedTrafficRules(_ document: TrafficRuleDocument) {
        do {
            try saveUnifiedTrafficRulesNow(document)
        } catch {
            appendLog("[RULES] unable to save unified rules: \(error.localizedDescription)\n")
            onToast?("Unable to save traffic rules", .error)
        }
    }

    @MainActor
    func saveUnifiedTrafficRulesNow(_ document: TrafficRuleDocument) throws {
        try validateTrafficRuleDocument(document)
        try trafficRuleStore.save(rules: document.rules)
        trafficRuleDocument = document
        synchronizeEffectiveTrafficRules(force: true)
    }

    func syncUnifiedTrafficRules() {
        synchronizeEffectiveTrafficRules(force: true)
    }

    func synchronizeEffectiveTrafficRules(force: Bool = false) {
        let mapRules = configuredMapRules()
        let breakpoints = configuredBreakpointRules()
        let legacyStateChanged = mapRules != appliedRules || breakpoints != appliedBreakpointRules

        appliedRules = mapRules
        appliedBreakpointRules = breakpoints

        guard force || legacyStateChanged else { return }

        service.replaceRules(effectiveTrafficRuleDocument())
    }

    func effectiveTrafficRuleDocument() -> TrafficRuleDocument {
        let legacyDocument = LegacyTrafficRuleAdapter.document(
            mapRules: Array(configuredMapRules().values),
            breakpoints: Array(configuredBreakpointRules().values),
            scripts: scripts
        )
        return mergedEffectiveDocument(with: legacyDocument)
    }

    private func configuredMapRules() -> [String: MapRule] {
        var result = rules.values.reduce(into: [String: MapRule]()) { rulesByKey, rule in
            rulesByKey[rule.key] = rule
        }

        let enabledCollections = collections
            .filter(\.isEnabled)
            .sorted { ($0.enabledAt ?? .distantPast) < ($1.enabledAt ?? .distantPast) }

        for collection in enabledCollections {
            for rule in collection.rules where rule.isEnabled {
                result[rule.key] = rule
            }
        }
        return result
    }

    private func configuredBreakpointRules() -> [String: FlowBreakpointRule] {
        breakpointRules.values.reduce(into: [String: FlowBreakpointRule]()) { rulesByKey, rule in
            rulesByKey[rule.key] = rule
        }
    }

    private func mergedEffectiveDocument(
        with legacyDocument: TrafficRuleDocument
    ) -> TrafficRuleDocument {
        var legacyByID = legacyDocument.rules.reduce(into: [UUID: TrafficRule]()) { rulesByID, rule in
            rulesByID[rule.id] = rule
        }

        let mergedUnifiedRules = trafficRuleDocument.rules.map { unifiedRule in
            guard var legacyRule = legacyByID.removeValue(forKey: unifiedRule.id) else {
                return unifiedRule
            }
            legacyRule.priority = unifiedRule.priority
            return legacyRule
        }

        var rules = mergedUnifiedRules
        var nextPriority = (rules.map(\.priority).max() ?? -1) + 1
        for legacyRule in legacyDocument.rules
        where legacyByID.removeValue(forKey: legacyRule.id) != nil && legacyRule.isEnabled {
            var appendedRule = legacyRule
            appendedRule.priority = nextPriority
            rules.append(appendedRule)
            nextPriority += 1
        }
        return TrafficRuleDocument(
            schemaVersion: trafficRuleDocument.schemaVersion,
            rules: rules
        )
    }

    private func validateTrafficRuleDocument(_ document: TrafficRuleDocument) throws {
        guard document.schemaVersion == TrafficRuleDocument.currentSchemaVersion else {
            throw TrafficRuleDocumentSaveError.unsupportedDocumentSchema(document.schemaVersion)
        }

        var ruleIDs = Set<UUID>()
        for rule in document.rules {
            guard rule.schemaVersion == TrafficRule.currentSchemaVersion else {
                throw TrafficRuleDocumentSaveError.unsupportedRuleSchema(
                    ruleName: rule.name,
                    version: rule.schemaVersion
                )
            }
            guard ruleIDs.insert(rule.id).inserted else {
                throw TrafficRuleDocumentSaveError.duplicateRuleID(rule.id)
            }
            let matcherErrors = rule.matcher.validationErrors
            guard matcherErrors.isEmpty else {
                throw TrafficRuleDocumentSaveError.invalidMatcher(
                    ruleName: rule.name,
                    errors: matcherErrors
                )
            }
        }
    }
}
