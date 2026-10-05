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

            }
            .store(in: &cancellables)

        service.flowEventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flow in
                guard let self else { return }
                self.enqueueBreakpointHits(from: [flow])
                guard let writer = self.sessionCaptureWriter,
                      let sessionID = self.activeCaptureSessionID else { return }
                writer.enqueue(flow, sessionID: sessionID)
            }
            .store(in: &cancellables)

        sessionCaptureWriter?.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                if let errorDescription = update.errorDescription {
                    self.appendLog("[SESSION] unable to persist flow batch: \(errorDescription)\n")
                    return
                }
                guard let index = self.captureSessions.firstIndex(where: { $0.id == update.sessionID }) else {
                    return
                }
                var session = self.captureSessions[index]
                session.flowCount += update.insertedFlowCount
                session.updatedAt = max(session.updatedAt, update.updatedAt)
                self.captureSessions[index] = session
            }
            .store(in: &cancellables)

        service.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                self.isRunning = running
                if !running {
                    self.breakpointQueue.removeAll()
                    self.activeBreakpointHit = nil
                }
                self.syncMacOSProxyOverride()
                if running {
                    self.service.applyTrafficProfile(self.activeTrafficProfile)
                }
            }
            .store(in: &cancellables)

        service.onLog = { [weak self] text in
            Task { @MainActor [weak self] in self?.appendLog(text) }
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
