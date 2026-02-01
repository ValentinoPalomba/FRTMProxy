import Foundation

extension ProxyViewModel {
    func mapResponse(body: String, status: Int? = nil, headers: [String: String]? = nil) {
        guard let flow = selectedFlow,
              let ruleInfo = mapRuleKey(for: flow) else { return }
        let preferredKey = ruleInfo.key
        let key = MapRuleKeyBuilder.disambiguatedKey(preferredKey: preferredKey, existingKeys: Set(rules.keys))
        let rule = MapRule(
            key: key,
            host: ruleInfo.host,
            path: ruleInfo.path,
            scheme: ruleInfo.scheme,
            request: ruleInfo.request,
            body: body,
            status: status ?? flow.response?.status ?? 200,
            headers: headers ?? flow.response?.headers ?? [:]
        )
        rules[rule.key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
    }

    @discardableResult
    func createRule(host: String, path: String) -> MapRule? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        if trimmedPath.isEmpty {
            trimmedPath = "/"
        }
        if !trimmedPath.hasPrefix("/") {
            trimmedPath = "/" + trimmedPath
        }

        let key = trimmedHost + trimmedPath
        guard rules[key] == nil else { return rules[key] }

        let rule = MapRule(
            key: key,
            host: trimmedHost,
            path: trimmedPath,
            scheme: "https",
            body: "",
            status: 200,
            headers: [:],
            isEnabled: true
        )
        rules[key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
        return rule
    }

    func setRule(_ key: String, enabled: Bool) {
        guard var rule = rules[key] else { return }
        rule.isEnabled = enabled
        rules[key] = rule
        persistRules()
        syncAppliedRules()
    }

    func updateRule(
        key: String,
        body: String,
        status: Int,
        headers: [String: String],
        isEnabled: Bool
    ) {
        guard var rule = rules[key] else { return }
        rule.body = body
        rule.status = status
        rule.headers = headers
        rule.isEnabled = isEnabled
        rules[key] = rule
        persistRules()
        record(rule: rule)
        syncAppliedRules()
    }

    func deleteRule(key: String) {
        rules.removeValue(forKey: key)
        persistRules()
        syncAppliedRules()
    }

    func retryFlow(with payload: MapEditorRetryPayload) {
        service.retryFlow(
            flowID: payload.flowID,
            method: payload.method,
            url: payload.url,
            body: payload.body,
            headers: payload.headers
        )
    }

    func applyMapLocal(
        requestBody: String?,
        requestHeaders: [String: String],
        responseBody: String,
        status: Int,
        headers: [String: String]
    ) {
        if let requestBody, let flowID = selectedFlow?.id {
            service.mockRequest(for: flowID, body: requestBody, headers: requestHeaders)
        }
        if let flowID = selectedFlow?.id {
            service.mockResponse(for: flowID, body: responseBody, status: status, headers: headers)
        }
    }

    func mapKey(for flow: MitmFlow) -> (key: String, host: String, path: String, scheme: String?)? {
        guard let urlString = flow.request?.url,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        let path = url.path
        return (key: host + path, host: host, path: path.isEmpty ? "/" : path, scheme: url.scheme)
    }

    func mapRuleKey(for flow: MitmFlow) -> (key: String, host: String, path: String, scheme: String?, request: MapRuleRequest?)? {
        guard let base = mapKey(for: flow) else { return nil }
        guard let request = flow.request else { return nil }
        let fullKey = MapRuleKeyBuilder.makeKey(
            host: base.host,
            path: base.path,
            method: request.method,
            url: request.url,
            headers: request.headers,
            body: request.body
        )
        return (
            key: fullKey,
            host: base.host,
            path: base.path,
            scheme: base.scheme,
            request: MapRuleRequest(method: request.method, url: request.url, headers: request.headers, body: request.body)
        )
    }

    func reapplyStoredRules() {
        appliedRules.removeAll()
        syncAppliedRules()
    }

    func record(rule: MapRule) {
        guard collectionRecorder.isRecording else { return }
        collectionRecorder.record(rule: rule)
        recordingRulesPreview = collectionRecorder.currentRules()
    }

    func captureRecordingRules(from flows: [MitmFlow]) {
        guard collectionRecorder.isRecording else { return }
        let candidates = flows
            .filter { !recordedFlowIDs.contains($0.id) && $0.response != nil }
            .sorted(by: { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) })

        var existingKeys = Set(collectionRecorder.currentRules().map(\.key))
        for flow in candidates {
            guard let response = flow.response,
                  let info = mapRuleKey(for: flow) else { continue }

            let key = MapRuleKeyBuilder.disambiguatedKey(preferredKey: info.key, existingKeys: existingKeys)
            existingKeys.insert(key)
            let rule = MapRule(
                key: key,
                host: info.host,
                path: info.path,
                scheme: info.scheme,
                request: info.request,
                body: response.body ?? "",
                status: response.status ?? 200,
                headers: response.headers ?? [:],
                isEnabled: true
            )
            record(rule: rule)
            recordedFlowIDs.insert(flow.id)
        }
    }

    func syncAppliedRules() {
        var merged: [String: MapRule] = [:]
        var orderedKeys: [String] = []

        func upsert(_ rule: MapRule) {
            if let index = orderedKeys.firstIndex(of: rule.key) {
                orderedKeys.remove(at: index)
            }
            orderedKeys.append(rule.key)
            merged[rule.key] = rule
        }

        for rule in rules.values.sorted(by: { $0.key < $1.key }) where rule.isEnabled {
            upsert(rule)
        }

        let enabledCollections = collections
            .filter { $0.isEnabled }
            .sorted(by: { ($0.enabledAt ?? Date.distantPast) < ($1.enabledAt ?? Date.distantPast) })

        for collection in enabledCollections {
            for rule in collection.rules where rule.isEnabled {
                upsert(rule)
            }
        }

        let oldKeys = Set(appliedRules.keys)
        let newKeys = Set(merged.keys)
        let removedKeys = oldKeys.subtracting(newKeys)
        for key in removedKeys {
            service.deleteRule(forKey: key)
        }

        for key in orderedKeys {
            guard let rule = merged[key] else { continue }
            if let existing = appliedRules[key], existing == rule {
                continue
            }
            service.mockRule(rule)
        }

        appliedRules = merged
    }
}
