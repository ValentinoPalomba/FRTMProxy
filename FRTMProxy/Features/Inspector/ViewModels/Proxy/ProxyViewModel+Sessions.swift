import Foundation

extension ProxyViewModel {
    @MainActor
    func handleUnexpectedProxyExit() {
        guard captureSessionCloseTask == nil, let sessionID = activeCaptureSessionID,
              let sessionStore else { return }
        let reason = String(localized: "The proxy stopped unexpectedly. The session may be incomplete; saved traffic remains available.", bundle: AppLocalization.bundle)
        activeCaptureSessionID = nil
        if let index = captureSessions.firstIndex(where: { $0.id == sessionID }) {
            captureSessions[index].incompleteReason = reason
        }
        appendLog("[SESSION] \(reason)\n")
        onToast?(reason, .error)
        let writer = sessionCaptureWriter
        captureSessionCloseTask = Task { @MainActor [weak self] in
            do {
                try await sessionStore.markSessionIncomplete(id: sessionID, reason: reason)
                await Task.yield()
                try await writer?.flush(sessionID: sessionID)
                try await sessionStore.closeSession(id: sessionID)
                self?.captureSessions = try await sessionStore.sessions()
            } catch {
                self?.appendLog("[SESSION] cannot close interrupted capture: \(error.localizedDescription)\n")
            }
            self?.captureSessionCloseTask = nil
        }
    }

    @MainActor
    func handleCaptureSaturation(sessionID: UUID) {
        guard activeCaptureSessionID == sessionID else { return }
        let reason = SessionCaptureWriter.CapacityError.saturated.localizedDescription
        activeCaptureSessionID = nil
        if let index = captureSessions.firstIndex(where: { $0.id == sessionID }) {
            captureSessions[index].incompleteReason = reason
        }
        appendLog("[SESSION] \(reason)\n")
        onToast?(reason, .error)
        stopProxy()
        guard let sessionStore else { return }
        let writer = sessionCaptureWriter
        captureSessionCloseTask = Task { @MainActor [weak self] in
            do {
                // Record incompleteness before attempting to drain accepted data.
                try await sessionStore.markSessionIncomplete(id: sessionID, reason: reason)
                try await writer?.flush(sessionID: sessionID)
                try await sessionStore.closeSession(id: sessionID)
                self?.captureSessions = try await sessionStore.sessions()
            } catch {
                self?.appendLog("[SESSION] cannot persist incomplete status: \(error.localizedDescription)\n")
            }
            self?.captureSessionCloseTask = nil
        }
    }

    func loadCaptureSessions() {
        guard captureSessionLoadTask == nil else { return }
        captureSessionLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if self.sessionStore == nil {
                    let store = try await Task.detached(priority: .userInitiated) {
                        try Self.makeDefaultSessionStore()
                    }.value
                    self.installSessionStore(store)
                }
                guard let sessionStore = self.sessionStore else { return }
                try await sessionStore.cleanupDeletedBodies()
                let stored = try await sessionStore.sessions()
                await MainActor.run {
                    self.captureSessions = stored
                    self.activeCaptureSessionID = stored.first(where: { $0.isActive && $0.incompleteReason == nil })?.id
                    self.captureSessionLoadTask = nil
                }
            } catch {
                await MainActor.run {
                    self.appendLog("[SESSION] unable to load sessions: \(error.localizedDescription)\n")
                    self.onToast?("Capture storage unavailable: \(error.localizedDescription)", .error)
                    self.captureSessionLoadTask = nil
                }
            }
        }
    }

    @MainActor
    @discardableResult
    func ensureCaptureSession(name: String? = nil) async -> Bool {
        await captureSessionLoadTask?.value
        await captureSessionCloseTask?.value
        if activeCaptureSessionID != nil { return true }
        guard let sessionStore else {
            onToast?("Capture storage is unavailable. Unlock the Keychain and reload Sessions before starting capture.", .error)
            return false
        }
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
            return true
        } catch {
            appendLog("[SESSION] unable to create session: \(error.localizedDescription)\n")
            onToast?("Cannot start capture: \(error.localizedDescription)", .error)
            return false
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

    @MainActor
    func importCaptureSession(_ prepared: SessionHARImporter.Prepared, name: String) async throws -> CaptureSession {
        await captureSessionLoadTask?.value
        guard let sessionStore else { throw SessionStoreError.database("Capture storage is unavailable") }
        let imported = try await sessionStore.importSession(prepared, name: name)
        captureSessions.insert(imported, at: 0)
        // The import has committed. A later refresh error must not offer a retry
        // that imports the same file twice.
        do { captureSessions = try await sessionStore.sessions() }
        catch { appendLog("[SESSION] imported capture; list refresh failed: \(error.localizedDescription)\n") }
        return imported
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
