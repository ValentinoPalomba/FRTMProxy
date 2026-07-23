import Foundation

extension ProxyViewModel {
    func currentWorkspaceBundle() -> WorkspaceBundle? {
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

        let manifest = WorkspaceManifest(
            identifier: "frtmproxy-workspace",
            displayName: "FRTMProxy Workspace",
            summary: "Traffic rules, scripts, and breakpoints",
            resources: resources
        )
        return WorkspaceBundle(manifest: manifest, resources: payloads)
    }

    func applyWorkspaceBundle(_ plan: WorkspaceImportPlan) throws -> WorkspaceImportResult {
        do {
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

        synchronizeEffectiveTrafficRules(force: true)

        for resource in plan.skippedResources {
            appendLog(
                "[WORKSPACE] skipped unsupported resource \(resource.reference.path)\n"
            )
        }
        let result = WorkspaceImportResult(
            appliedResources: plan.resourcesToApply,
            skippedResources: plan.skippedResources
        )
        onToast?("Workspace imported", .success)
        return result
    }
}
