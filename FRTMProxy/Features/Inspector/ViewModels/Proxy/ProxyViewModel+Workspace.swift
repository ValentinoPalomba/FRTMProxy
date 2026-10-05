import Foundation

extension ProxyViewModel {
    func currentWorkspaceBundle(defaults: UserDefaults = .standard) -> WorkspaceBundle? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        var resources = WorkspaceResources()
        var payloads: [WorkspaceResourcePayload] = []

        let rulesReference = WorkspaceResourceReference(
            identifier: "traffic-rules",
            path: "rules/traffic-rules.json"
        )
        resources.rules = [rulesReference]
        guard let rulesData = try? encoder.encode(effectiveTrafficRuleDocument()) else { return nil }
        payloads.append(.init(
            kind: .rule,
            reference: rulesReference,
            data: rulesData
        ))

        if !scripts.isEmpty {
            let reference = WorkspaceResourceReference(identifier: "scripts", path: "scripts/scripts.json")
            resources.scripts = [reference]
            guard let scriptsData = try? encoder.encode(scripts) else { return nil }
            payloads.append(.init(kind: .script, reference: reference, data: scriptsData))
        }

        if !breakpointRules.isEmpty {
            let reference = WorkspaceResourceReference(
                identifier: "breakpoints",
                path: "breakpoints/breakpoints.json"
            )
            resources.breakpoints = [reference]
            guard let breakpointsData = try? encoder.encode(
                breakpointRules.values.sorted { $0.key < $1.key }
            ) else { return nil }
            payloads.append(.init(
                kind: .breakpoint,
                reference: reference,
                data: breakpointsData
            ))
        }

        let preferences: WorkspaceInspectorPreferences
        do { preferences = try .read(from: defaults) }
        catch {
            appendLog("[WORKSPACE] unable to export inspector preferences: \(error.localizedDescription)\n")
            onToast?("Unable to export unreadable inspector preferences", .error)
            return nil
        }
        let manifest = WorkspaceManifest(
            identifier: "frtmproxy-workspace",
            displayName: "FRTMProxy Workspace",
            summary: "Traffic rules, scripts, and breakpoints",
            resources: resources,
            inspectorPreferences: preferences
        )
        return WorkspaceBundle(manifest: manifest, resources: payloads)
    }

    func applyWorkspaceBundle(_ plan: WorkspaceImportPlan, defaults: UserDefaults = .standard) throws -> WorkspaceImportResult {
        do {
            try plan.bundle.manifest.inspectorPreferences?.validate()
            if let document = plan.trafficRuleDocument {
                try trafficRuleStore.save(rules: document.rules)
            }
        } catch {
            appendLog("[WORKSPACE] unable to apply import: \(error.localizedDescription)\n")
            throw error
        }

        if let document = plan.trafficRuleDocument {
            trafficRuleDocument = document
        }
        if let importedScripts = plan.scripts {
            scripts = importedScripts
            scriptStore.save(importedScripts)
        }
        if let importedBreakpoints = plan.breakpointRules {
            breakpointRules = importedBreakpoints
            breakpointStore.save(
                breakpoints: importedBreakpoints.values.sorted { $0.key < $1.key }
            )
        }

        try plan.bundle.manifest.inspectorPreferences?.apply(to: defaults)
        synchronizeEffectiveTrafficRules(force: true)

        for resource in plan.skippedResources {
            appendLog(
                "[WORKSPACE] skipped unsupported resource \(resource.reference.path)\n"
            )
        }
        let result = WorkspaceImportResult(
            appliedResources: plan.resourcesToApply,
            skippedResources: plan.skippedResources,
            inspectorPreferencesApplied: plan.bundle.manifest.inspectorPreferences != nil
        )
        onToast?("Workspace imported", .success)
        return result
    }
}
