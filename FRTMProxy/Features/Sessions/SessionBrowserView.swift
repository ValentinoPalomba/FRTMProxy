import SwiftUI

struct SessionBrowserView: View {
    typealias LoadPage = (UUID, CaptureSessionPageCursor?, Int) async throws -> CaptureSessionPage
    typealias DeleteSession = (UUID) async throws -> Void
    typealias SetMetadata = (String, UUID, String?, Bool) async throws -> Void
    typealias CloseSession = (UUID) async throws -> Void

    let sessions: [CaptureSession]
    @Binding var selectedSessionID: UUID?
    let colors: DesignSystem.ColorPalette
    let pageSize: Int
    let loadPage: LoadPage
    let deleteSession: DeleteSession
    let setMetadata: SetMetadata
    let closeSession: CloseSession
    let onOpenFlow: (MitmFlow) -> Void

    @State private var timelineModel = SessionTimelineModel()
    @State private var pendingDeletion: CaptureSession?
    @State private var editingFlow: CaptureSessionFlow?
    @State private var actionErrorMessage: String?
    @State private var isPerformingSessionAction = false

    init(
        sessions: [CaptureSession],
        selectedSessionID: Binding<UUID?>,
        colors: DesignSystem.ColorPalette,
        pageSize: Int = 200,
        loadPage: @escaping LoadPage,
        deleteSession: @escaping DeleteSession,
        setMetadata: @escaping SetMetadata,
        closeSession: @escaping CloseSession,
        onOpenFlow: @escaping (MitmFlow) -> Void = { _ in }
    ) {
        self.sessions = sessions
        _selectedSessionID = selectedSessionID
        self.colors = colors
        self.pageSize = pageSize
        self.loadPage = loadPage
        self.deleteSession = deleteSession
        self.setMetadata = setMetadata
        self.closeSession = closeSession
        self.onOpenFlow = onOpenFlow
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebarView(
                sessions: sessions,
                selection: $selectedSessionID,
                colors: colors,
                onClose: close,
                onDelete: requestDeletion
            )
            .navigationTitle("Sessions")
        } detail: {
            if let selectedSession {
                SessionTimelineView(
                    session: selectedSession,
                    model: timelineModel,
                    colors: colors,
                    onReload: reloadSelectedSession,
                    onLoadMore: loadNextPage,
                    onEditMetadata: { editingFlow = $0 },
                    onToggleBookmark: toggleBookmark,
                    onOpenFlow: onOpenFlow
                )
                .navigationTitle(selectedSession.name)
                .toolbar {
                    if selectedSession.isActive {
                        ToolbarItem {
                            Button("Close Session", systemImage: "stop.circle") {
                                close(selectedSession)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPerformingSessionAction)
                        }
                    }
                    ToolbarItem {
                        Button("Delete Session", systemImage: "trash", role: .destructive) {
                            requestDeletion(selectedSession)
                        }
                        .disabled(selectedSession.isActive || isPerformingSessionAction)
                        .help(
                            selectedSession.isActive
                                ? "Close the active session before deleting it."
                                : "Permanently delete this captured session."
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose a capture from the sidebar to inspect its timeline.")
                )
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task(id: selectedSessionID) {
            await loadSelectedSession()
        }
        .sheet(item: $editingFlow) { flow in
            SessionFlowMetadataSheet(
                flow: flow,
                colors: colors,
                onSave: { note, isBookmarked in
                    guard let selectedSessionID else { return }
                    try await setMetadata(flow.id, selectedSessionID, note, isBookmarked)
                    timelineModel.updateMetadata(
                        flowID: flow.id,
                        note: note,
                        isBookmarked: isBookmarked
                    )
                }
            )
        }
        .confirmationDialog(
            "Delete captured session?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) {
                guard let pendingDeletion, !pendingDeletion.isActive else { return }
                delete(pendingDeletion)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently removes the session and its captured flows. This action cannot be undone.")
        }
        .alert(
            "Session Action Failed",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "Unknown error")
        }
    }

    private var selectedSession: CaptureSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    private func loadSelectedSession() async {
        guard let selectedSessionID else { return }
        timelineModel.reset(for: selectedSessionID)
        timelineModel.startLoading()
        do {
            let page = try await loadPage(selectedSessionID, nil, pageSize)
            guard !Task.isCancelled else { return }
            timelineModel.receive(page, for: selectedSessionID)
        } catch is CancellationError {
            if timelineModel.sessionID == selectedSessionID {
                timelineModel.isLoading = false
            }
        } catch {
            timelineModel.fail(error, for: selectedSessionID)
        }
    }

    private func loadNextPage() {
        guard let selectedSessionID,
              let cursor = timelineModel.nextCursor,
              timelineModel.canLoadMore else { return }
        timelineModel.startLoading()
        Task {
            do {
                let page = try await loadPage(selectedSessionID, cursor, pageSize)
                timelineModel.receive(page, for: selectedSessionID)
            } catch {
                timelineModel.fail(error, for: selectedSessionID)
            }
        }
    }

    private func reloadSelectedSession() {
        Task {
            await loadSelectedSession()
        }
    }

    private func toggleBookmark(_ flow: CaptureSessionFlow) {
        guard let selectedSessionID else { return }
        let newValue = !flow.isBookmarked
        Task {
            do {
                try await setMetadata(flow.id, selectedSessionID, flow.note, newValue)
                timelineModel.updateMetadata(flowID: flow.id, note: flow.note, isBookmarked: newValue)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func close(_ session: CaptureSession) {
        guard session.isActive else { return }
        isPerformingSessionAction = true
        Task {
            defer { isPerformingSessionAction = false }
            do {
                try await closeSession(session.id)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func requestDeletion(_ session: CaptureSession) {
        guard !session.isActive else { return }
        pendingDeletion = session
    }

    private func delete(_ session: CaptureSession) {
        pendingDeletion = nil
        guard !session.isActive else { return }
        isPerformingSessionAction = true
        Task {
            defer { isPerformingSessionAction = false }
            do {
                try await deleteSession(session.id)
                if selectedSessionID == session.id {
                    selectedSessionID = nil
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}
