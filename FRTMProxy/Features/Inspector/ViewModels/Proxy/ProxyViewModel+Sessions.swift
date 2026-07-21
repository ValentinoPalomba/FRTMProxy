import Foundation

extension ProxyViewModel {
    func loadCaptureSessions() {
        guard let sessionStore else { return }
        Task {
            do {
                let stored = try await sessionStore.sessions()
                await MainActor.run {
                    captureSessions = stored
                    activeCaptureSessionID = stored.first(where: \.isActive)?.id
                }
            } catch {
                await MainActor.run {
                    appendLog("[SESSION] unable to load sessions: \(error.localizedDescription)\n")
                }
            }
        }
    }

    @MainActor
    func ensureCaptureSession(name: String? = nil) async {
        guard activeCaptureSessionID == nil, let sessionStore else { return }
        do {
            let session = try await sessionStore.createSession(name: name ?? defaultCaptureSessionName())
            activeCaptureSessionID = session.id
            captureSessions.insert(session, at: 0)
        } catch {
            appendLog("[SESSION] unable to create session: \(error.localizedDescription)\n")
        }
    }

    func closeActiveCaptureSession() {
        guard let sessionStore, let sessionID = activeCaptureSessionID else { return }
        activeCaptureSessionID = nil
        Task {
            do {
                try await sessionStore.closeSession(id: sessionID)
                let stored = try await sessionStore.sessions()
                await MainActor.run { captureSessions = stored }
            } catch {
                await MainActor.run {
                    appendLog("[SESSION] unable to close session: \(error.localizedDescription)\n")
                }
            }
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
        try await sessionStore.closeSession(id: id)
        if activeCaptureSessionID == id {
            activeCaptureSessionID = nil
        }
        captureSessions = try await sessionStore.sessions()
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
