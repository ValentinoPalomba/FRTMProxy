import Combine
import Foundation

extension ProxyViewModel {
    func bind() {
        let flowProcessingQueue = DispatchQueue(label: "com.frtmproxy.flow-binding", qos: .userInitiated)
        service.flowsPublisher
            .receive(on: flowProcessingQueue)
            .throttle(for: .milliseconds(120), scheduler: flowProcessingQueue, latest: true)
            .map { map in
                map.values.sorted(by: { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) })
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sorted in
                guard let self else { return }
                let enriched = self.enrichFlowsWithCachedApps(sorted)
                self.flows = enriched
                if self.selectedFlowID == nil {
                    self.selectedFlowID = enriched.first?.id
                }
                self.captureRecordingRules(from: enriched)
                self.enqueueBreakpointHits(from: enriched)
                self.resolveClientAppsIfNeeded(in: enriched)
                self.processAlerts(in: enriched)
                for flow in enriched where flow.event == "response" && !self.processedScriptFlowIDs.contains(flow.id) {
                    self.processedScriptFlowIDs.insert(flow.id)
                    self.processScripts(for: flow)
                }
                // Evita la crescita illimitata del set (resettato solo in clear()):
                // oltre soglia conserva solo gli id dei flussi ancora presenti.
                if self.processedScriptFlowIDs.count > 2000 {
                    self.processedScriptFlowIDs.formIntersection(Set(enriched.map(\.id)))
                }
            }
            .store(in: &cancellables)

        service.flowEventsPublisher
            .sink { [weak self] flow in
                guard let self,
                      let store = self.sessionStore,
                      let sessionID = self.activeCaptureSessionID else { return }
                let flowID = flow.id
                Task {
                    do {
                        try await store.upsert(flow: flow, in: sessionID)
                        let updatedSession = try await store.session(id: sessionID)
                        await MainActor.run {
                            guard let updatedSession,
                                  let index = self.captureSessions.firstIndex(where: { $0.id == sessionID }) else {
                                return
                            }
                            self.captureSessions[index] = updatedSession
                        }
                    } catch {
                        await MainActor.run {
                            self.appendLog("[SESSION] unable to persist flow \(flowID): \(error.localizedDescription)\n")
                        }
                    }
                }
            }
            .store(in: &cancellables)

        service.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.isRunning = running
                self.updateProxySelfHealingState()
                if running {
                    self.service.applyTrafficProfile(self.activeTrafficProfile)
                }
            }
            .store(in: &cancellables)

        service.onLog = { [weak self] text in
            DispatchQueue.main.async {
                self?.appendLog(text)
            }
        }
    }

    func enrichFlowsWithCachedApps(_ flows: [MitmFlow]) -> [MitmFlow] {
        var enriched = flows
        for index in enriched.indices {
            guard enriched[index].clientApp == nil,
                  let clientPort = enriched[index].client?.port,
                  !enriched[index].clientIP.isEmpty else {
                continue
            }
            let key = connectionKey(clientIP: enriched[index].clientIP, clientPort: clientPort, proxyPort: activePort)
            if let app = clientAppByConnectionKey[key] {
                enriched[index].clientApp = app
            }
        }
        return enriched
    }

    func resolveClientAppsIfNeeded(in flows: [MitmFlow]) {
        let proxyPort = activePort
        let maxConcurrentResolutions = 4
        let maxNewResolutionsPerUpdate = 3

        if resolvingConnectionKeys.count >= maxConcurrentResolutions {
            return
        }

        var started = 0
        for flow in flows.prefix(120) {
            if started >= maxNewResolutionsPerUpdate || resolvingConnectionKeys.count >= maxConcurrentResolutions {
                break
            }
            guard flow.clientApp == nil,
                  let clientPort = flow.client?.port,
                  isLoopbackClientIP(flow.clientIP) else {
                continue
            }

            let key = connectionKey(clientIP: flow.clientIP, clientPort: clientPort, proxyPort: proxyPort)
            if resolvingConnectionKeys.contains(key) || clientAppByConnectionKey[key] != nil {
                continue
            }
            resolvingConnectionKeys.insert(key)
            started += 1

            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let app = await self.clientAppResolver.resolve(clientPort: clientPort, proxyPort: proxyPort)
                await MainActor.run {
                    self.resolvingConnectionKeys.remove(key)
                    guard let app else { return }
                    self.clientAppByConnectionKey[key] = app
                    var updated = self.flows
                    var changed = false
                    for idx in updated.indices where updated[idx].clientApp == nil {
                        guard let existingPort = updated[idx].client?.port else { continue }
                        let existingKey = self.connectionKey(clientIP: updated[idx].clientIP, clientPort: existingPort, proxyPort: proxyPort)
                        if existingKey == key {
                            updated[idx].clientApp = app
                            changed = true
                        }
                    }
                    if changed {
                        self.flows = updated
                    }
                }
            }
        }
    }

    func connectionKey(clientIP: String, clientPort: Int, proxyPort: Int) -> String {
        "\(clientIP.trimmingCharacters(in: .whitespacesAndNewlines))|\(clientPort)|\(proxyPort)"
    }

    func isLoopbackClientIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "::1" || trimmed == "localhost" {
            return true
        }
        return trimmed.hasPrefix("127.")
    }
}
