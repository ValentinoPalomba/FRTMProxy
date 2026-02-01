import Foundation

extension ProxyViewModel {
    func applyAlertRules(_ rules: [AlertRule]) {
        let trimmed: [AlertRule] = rules.map {
            AlertRule(
                id: $0.id,
                name: $0.name,
                query: $0.query,
                isEnabled: $0.isEnabled,
                createdAt: $0.createdAt
            )
        }

        let previousQueries = alertRuleQueryByID
        alertRuleQueryByID = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.id, $0.query) })

        let currentIDs = Set(trimmed.map(\.id))
        let removedIDs = Set(previousQueries.keys).subtracting(currentIDs)
        if !removedIDs.isEmpty {
            for id in removedIDs {
                removeTriggeredAlerts(forRuleID: id)
            }
        }

        for rule in trimmed {
            let previous = previousQueries[rule.id]
            if let previous, previous != rule.query {
                removeTriggeredAlerts(forRuleID: rule.id)
            }
        }

        alertRules = trimmed
        alertFiltersByRuleID = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.id, FlowFilter(searchText: $0.query)) })
    }

    func removeTriggeredAlerts(forRuleID id: UUID) {
        let prefix = id.uuidString + "|"
        triggeredAlertKeys = Set(triggeredAlertKeys.filter { !$0.hasPrefix(prefix) })
    }

    func processAlerts(in flows: [MitmFlow]) {
        guard alertsEnabled else { return }
        guard !alertRules.isEmpty else { return }

        let enabledRules = alertRules.filter(\.isEnabled)
        guard !enabledRules.isEmpty else { return }

        let candidates = flows.filter { $0.response != nil && !seenAlertFlowIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        for rule in enabledRules {
            let filter = alertFiltersByRuleID[rule.id] ?? FlowFilter(searchText: rule.query)
            let matching = filter.apply(to: candidates)
            for flow in matching {
                let key = rule.id.uuidString + "|" + flow.id
                guard !triggeredAlertKeys.contains(key) else { continue }
                triggeredAlertKeys.insert(key)
                notifyAlert(rule: rule, flow: flow)
            }
        }

        seenAlertFlowIDs.formUnion(candidates.map(\.id))
        if seenAlertFlowIDs.count > 2_000 {
            let responseFlowIDs = Set(flows.filter { $0.response != nil }.map(\.id))
            seenAlertFlowIDs = seenAlertFlowIDs.intersection(responseFlowIDs)
        }

        if triggeredAlertKeys.count > 20_000 {
            triggeredAlertKeys.removeAll()
        }
    }

    func notifyAlert(rule: AlertRule, flow: MitmFlow) {
        let title = rule.name.isEmpty ? "FRTMProxy Alert" : rule.name
        let method = flow.request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let url = flow.request?.url.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = flow.response?.status.map(String.init) ?? "—"
        let client = flow.clientIP

        var body = ""
        if !method.isEmpty && !url.isEmpty {
            body = "\(method) \(url)"
        } else if !url.isEmpty {
            body = url
        } else {
            body = flow.sharePreviewTitle
        }
        body += "\nStatus: \(status)"
        if !client.isEmpty {
            body += "\nClient: \(client)"
        }

        Task {
            await AlertNotificationService.shared.postAlertNotification(title: title, body: body)
        }
    }
}
