import Foundation

extension ProxyViewModel {
    func isBreakpointEnabled(for flow: MitmFlow, phase: FlowBreakpointPhase) -> Bool {
        guard let info = mapKey(for: flow) else { return false }
        guard let rule = breakpointRules[info.key], rule.isEnabled else { return false }
        switch phase {
        case .request:
            return rule.interceptRequest
        case .response:
            return rule.interceptResponse
        }
    }

    func setBreakpoint(for flow: MitmFlow, phase: FlowBreakpointPhase, enabled: Bool) {
        guard let info = mapKey(for: flow) else { return }
        var rule = breakpointRules[info.key] ?? FlowBreakpointRule(
            key: info.key,
            host: info.host,
            path: info.path,
            scheme: info.scheme,
            interceptRequest: false,
            interceptResponse: false,
            isEnabled: true
        )
        switch phase {
        case .request:
            rule.interceptRequest = enabled
        case .response:
            rule.interceptResponse = enabled
        }
        if rule.interceptRequest || rule.interceptResponse {
            rule.isEnabled = true
        } else {
            rule.isEnabled = false
        }

        saveBreakpointRule(rule)
    }

    func removeBreakpoint(for flow: MitmFlow) {
        guard let info = mapKey(for: flow) else { return }
        deleteBreakpoint(key: info.key)
    }

    func createBreakpoint(host: String, path: String, interceptRequest: Bool, interceptResponse: Bool) -> FlowBreakpointRule? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else { return nil }
        if trimmedPath.isEmpty {
            trimmedPath = "/"
        }
        if !trimmedPath.hasPrefix("/") {
            trimmedPath = "/" + trimmedPath
        }
        guard interceptRequest || interceptResponse else { return nil }

        let key = trimmedHost + trimmedPath
        let rule = FlowBreakpointRule(
            key: key,
            host: trimmedHost,
            path: trimmedPath,
            scheme: "https",
            interceptRequest: interceptRequest,
            interceptResponse: interceptResponse,
            isEnabled: true
        )
        saveBreakpointRule(rule)
        return rule
    }

    func setBreakpointEnabled(_ key: String, enabled: Bool) {
        guard var rule = breakpointRules[key] else { return }
        if enabled && !rule.interceptRequest && !rule.interceptResponse {
            rule.interceptRequest = true
        }
        rule.isEnabled = enabled && (rule.interceptRequest || rule.interceptResponse)
        saveBreakpointRule(rule)
    }

    func updateBreakpointPhases(key: String, request: Bool, response: Bool) {
        guard var rule = breakpointRules[key] else { return }
        rule.interceptRequest = request
        rule.interceptResponse = response
        rule.isEnabled = rule.isEnabled && (request || response)
        if !request && !response {
            rule.isEnabled = false
        }
        saveBreakpointRule(rule)
    }

    func deleteBreakpoint(key: String) {
        breakpointRules.removeValue(forKey: key)
        persistBreakpoints()
        syncBreakpointRules()
    }

    func flow(withID id: String) -> MitmFlow? {
        flows.first(where: { $0.id == id })
    }

    func continueActiveBreakpoint(using editor: MapEditorViewModel) {
        guard let hit = activeBreakpointHit,
              let flow = flow(withID: hit.flowID) else { return }

        switch hit.phase {
        case .request:
            guard let retryPayload = editor.retryPayload() else { return }
            let requestPayload = BreakpointRequestPayload(
                method: retryPayload.method,
                url: retryPayload.url,
                headers: retryPayload.headers,
                body: retryPayload.body
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .request,
                requestPayload: requestPayload,
                responsePayload: nil
            )
        case .response:
            let defaultStatus = flow.response?.status ?? 200
            guard let payload = editor.payload(defaultStatus: defaultStatus) else { return }
            let responsePayload = BreakpointResponsePayload(
                status: payload.responseStatus,
                headers: payload.responseHeaders,
                body: payload.responseBody
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .response,
                requestPayload: nil,
                responsePayload: responsePayload
            )
        }

        consumeActiveBreakpoint()
    }

    func skipActiveBreakpoint() {
        guard let hit = activeBreakpointHit,
              let flow = flow(withID: hit.flowID) else { return }
        switch hit.phase {
        case .request:
            guard let request = flow.request else { return }
            let payload = BreakpointRequestPayload(
                method: request.method,
                url: request.url,
                headers: request.headers,
                body: request.body
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .request,
                requestPayload: payload,
                responsePayload: nil
            )
        case .response:
            guard let response = flow.response else { return }
            let payload = BreakpointResponsePayload(
                status: response.status ?? 200,
                headers: response.headers ?? [:],
                body: response.body ?? ""
            )
            service.resumeBreakpoint(
                flowID: hit.flowID,
                phase: .response,
                requestPayload: nil,
                responsePayload: payload
            )
        }
        consumeActiveBreakpoint()
    }

    func saveBreakpointRule(_ rule: FlowBreakpointRule) {
        breakpointRules[rule.key] = rule
        persistBreakpoints()
        syncBreakpointRules()
    }

    func syncBreakpointRules() {
        synchronizeEffectiveTrafficRules()
    }

    func enqueueBreakpointHits(from flows: [MitmFlow]) {
        var waitingIDs: Set<String> = []

        for flow in flows {
            guard let breakpoint = flow.breakpoint,
                  breakpoint.state == .waiting else { continue }

            let hit = FlowBreakpointHit(
                flowID: flow.id,
                phase: breakpoint.phase,
                key: breakpoint.key,
                timestamp: flow.timestamp
            )
            waitingIDs.insert(hit.id)

            if !breakpointQueue.contains(where: { $0.id == hit.id }) {
                breakpointQueue.append(hit)
            }
        }

        breakpointQueue.removeAll { !waitingIDs.contains($0.id) }

        if let active = activeBreakpointHit, !waitingIDs.contains(active.id) {
            activeBreakpointHit = nil
        }

        if activeBreakpointHit == nil {
            activeBreakpointHit = breakpointQueue.first
        }
    }

    func consumeActiveBreakpoint() {
        guard let hit = activeBreakpointHit else { return }
        breakpointQueue.removeAll { $0.id == hit.id }
        activeBreakpointHit = breakpointQueue.first
    }
}
