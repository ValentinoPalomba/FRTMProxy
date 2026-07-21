import Foundation

extension ProxyViewModel {
    func currentWorkspaceBundle() -> WorkspaceBundle? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            var resources = WorkspaceResources()
            var payloads: [WorkspaceResourcePayload] = []

            let rulesReference = WorkspaceResourceReference(
                identifier: "traffic-rules",
                path: "rules/traffic-rules.json"
            )
            resources.rules = [rulesReference]
            payloads.append(.init(
                kind: .rule,
                reference: rulesReference,
                data: try encoder.encode(trafficRuleDocument)
            ))

            if !scripts.isEmpty {
                let reference = WorkspaceResourceReference(identifier: "scripts", path: "scripts/scripts.json")
                resources.scripts = [reference]
                payloads.append(.init(kind: .script, reference: reference, data: try encoder.encode(scripts)))
            }

            if !breakpointRules.isEmpty {
                let reference = WorkspaceResourceReference(
                    identifier: "breakpoints",
                    path: "breakpoints/breakpoints.json"
                )
                resources.breakpoints = [reference]
                payloads.append(.init(
                    kind: .breakpoint,
                    reference: reference,
                    data: try encoder.encode(breakpointRules.values.sorted { $0.key < $1.key })
                ))
            }

            let manifest = WorkspaceManifest(
                identifier: "frtmproxy-workspace",
                displayName: "FRTMProxy Workspace",
                summary: "Traffic rules, scripts, and breakpoints",
                resources: resources
            )
            return WorkspaceBundle(manifest: manifest, resources: payloads)
        } catch {
            appendLog("[WORKSPACE] unable to prepare export: \(error.localizedDescription)\n")
            return nil
        }
    }

    func applyWorkspaceBundle(_ bundle: WorkspaceBundle) {
        let decoder = JSONDecoder()
        do {
            for payload in bundle.resources {
                switch payload.kind {
                case .rule:
                    saveUnifiedTrafficRules(try decoder.decode(TrafficRuleDocument.self, from: payload.data))
                case .script:
                    scripts = try decoder.decode([ScriptRule].self, from: payload.data)
                    persistScripts()
                case .breakpoint:
                    let imported = try decoder.decode([FlowBreakpointRule].self, from: payload.data)
                    breakpointRules = Dictionary(uniqueKeysWithValues: imported.map { ($0.key, $0) })
                    persistBreakpoints()
                    syncBreakpointRules()
                case .profile, .session, .policy:
                    appendLog("[WORKSPACE] validated \(payload.reference.path); this resource is not applied by this version\n")
                }
            }
            onToast?("Workspace imported", .success)
        } catch {
            appendLog("[WORKSPACE] unable to apply import: \(error.localizedDescription)\n")
            onToast?("Unable to apply workspace", .error)
        }
    }
}
