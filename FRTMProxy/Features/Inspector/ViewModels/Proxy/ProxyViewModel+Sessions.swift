import Foundation

extension ProxyViewModel {
    func loadCaptureSessions() {
        guard let sessionStore, captureSessionLoadTask == nil else { return }
        captureSessionLoadTask = Task { [weak self] in
            do {
                let stored = try await sessionStore.sessions()
                await MainActor.run {
                    guard let self else { return }
                    self.captureSessions = stored
                    self.activeCaptureSessionID = stored.first(where: \.isActive)?.id
                    self.captureSessionLoadTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.appendLog("[SESSION] unable to load sessions: \(error.localizedDescription)\n")
                    self?.captureSessionLoadTask = nil
                }
            }
        }
    }

    @MainActor
    func ensureCaptureSession(name: String? = nil) async {
        await captureSessionLoadTask?.value
        await captureSessionCloseTask?.value
        guard activeCaptureSessionID == nil, let sessionStore else { return }
        do {
            let session = try await sessionStore.activeSessionOrCreate(
                name: name ?? defaultCaptureSessionName(),
                at: .now
            )
            activeCaptureSessionID = session.id
            if let index = captureSessions.firstIndex(where: { $0.id == session.id }) {
                captureSessions[index] = session
            } else {
                captureSessions.insert(session, at: 0)
            }
        } catch {
            appendLog("[SESSION] unable to create session: \(error.localizedDescription)\n")
        }
    }

    @MainActor
    func closeActiveCaptureSession() {
        guard captureSessionCloseTask == nil,
              let sessionStore,
              let sessionID = activeCaptureSessionID else {
            return
        }
        let writer = sessionCaptureWriter
        captureSessionCloseTask = Task { @MainActor [weak self] in
            // Allow flow events already scheduled on the main queue to enter the
            // writer before placing its close barrier.
            await Task.yield()
            self?.activeCaptureSessionID = nil
            do {
                try await writer?.flush(sessionID: sessionID)
                try await sessionStore.closeSession(id: sessionID)
                let stored = try await sessionStore.sessions()
                self?.captureSessions = stored
            } catch {
                self?.activeCaptureSessionID = sessionID
                self?.appendLog("[SESSION] unable to close session: \(error.localizedDescription)\n")
            }
            self?.captureSessionCloseTask = nil
        }
    }

    func deleteCaptureSession(_ id: UUID) {
        guard let sessionStore, id != activeCaptureSessionID else { return }
        Task {
            do {
                try await sessionStore.deleteSession(id: id)
                let stored = try await sessionStore.sessions()
                await MainActor.run { captureSessions = stored }
            } catch {
                await MainActor.run {
                    appendLog("[SESSION] unable to delete session: \(error.localizedDescription)\n")
                }
            }
        }
    }

    @MainActor
    func deleteCaptureSessionNow(_ id: UUID) async throws {
        guard let sessionStore, id != activeCaptureSessionID else { return }
        try await sessionStore.deleteSession(id: id)
        captureSessions = try await sessionStore.sessions()
    }

    @MainActor
    func closeCaptureSessionNow(_ id: UUID) async throws {
        guard let sessionStore else { return }
        let wasActive = activeCaptureSessionID == id
        if wasActive {
            await Task.yield()
            activeCaptureSessionID = nil
        }
        do {
            if wasActive {
                try await sessionCaptureWriter?.flush(sessionID: id)
            }
            try await sessionStore.closeSession(id: id)
            captureSessions = try await sessionStore.sessions()
        } catch {
            if wasActive {
                activeCaptureSessionID = id
            }
            throw error
        }
    }

    func setCaptureFlowMetadata(
        flowID: String,
        sessionID: UUID,
        note: String?,
        isBookmarked: Bool
    ) async throws {
        guard let sessionStore else { return }
        try await sessionStore.setMetadata(
            flowID: flowID,
            sessionID: sessionID,
            note: note,
            isBookmarked: isBookmarked
        )
    }

    @MainActor
    func openStoredFlow(_ flow: MitmFlow) {
        if let index = flows.firstIndex(where: { $0.id == flow.id }) {
            flows[index] = flow
        } else {
            flows.append(flow)
        }
        selectedFlowID = flow.id
    }

    func loadCaptureSessionPage(
        sessionID: UUID,
        after cursor: CaptureSessionPageCursor? = nil,
        limit: Int = 500
    ) async throws -> CaptureSessionPage {
        guard let sessionStore else {
            return CaptureSessionPage(flows: [], nextCursor: nil, corruptFlowIDs: [])
        }
        return try await sessionStore.page(in: sessionID, after: cursor, limit: limit)
    }

    private func defaultCaptureSessionName() -> String {
        "Capture \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    }
}
