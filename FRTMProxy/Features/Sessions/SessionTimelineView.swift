import SwiftUI

struct SessionTimelineView: View {
    let session: CaptureSession
    let model: SessionTimelineModel
    let colors: DesignSystem.ColorPalette
    let onReload: () -> Void
    let onLoadMore: () -> Void
    let onEditMetadata: (CaptureSessionFlow) -> Void
    let onToggleBookmark: (CaptureSessionFlow) -> Void
    let onOpenFlow: (MitmFlow) -> Void
    let onExportSession: (Bool) -> Void

    @State private var selectedFlowID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionTimelineHeader(session: session, colors: colors)

            if !model.flows.isEmpty {
                Menu("Export HAR…", systemImage: "square.and.arrow.up") {
                    Button("Entire Session — Redacted") { onExportSession(true) }
                        .disabled(session.isActive)
                    Button("Entire Session — Full Capture (includes secrets)") { onExportSession(false) }
                        .disabled(session.isActive)
                    Divider()
                    Button("Loaded Flows — Redacted (bodies omitted)") {
                        SessionHARExporter.export(flows: model.flows.map(\.flow), redacted: true)
                    }
                    Button("Loaded Flows — Full Capture (includes secrets)") {
                        SessionHARExporter.export(flows: model.flows.map(\.flow), redacted: false)
                    }
                }
                .menuStyle(.borderlessButton)
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textPrimary)
                .fixedSize()
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .help(session.isActive ? "Close the active session before exporting its complete capture. Loaded flows can be exported now." : "Export the complete capture or the loaded page.")
            }

            if !model.corruptFlowIDs.isEmpty {
                SessionCorruptionNotice(count: model.corruptFlowIDs.count, colors: colors)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

            if model.isLoading && !model.hasLoadedPage {
                StateView(kind: .loading(message: "Loading captured flows…"), palette: colors)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage, !model.hasLoadedPage {
                StateView(kind: .failed(title: "Unable to Load Session", message: errorMessage, retry: onReload), palette: colors)
            } else if model.flows.isEmpty {
                StateView(kind: .empty(title: "No Captured Flows", message: "This session does not contain any readable flows.", systemImage: "network.slash"), palette: colors)
            } else {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Text("")
                        .frame(width: DesignSystem.Metrics.scaled(18))
                    Text("Time")
                        .frame(width: DesignSystem.Metrics.scaled(78), alignment: .leading)
                    Text("Method")
                        .frame(width: DesignSystem.Metrics.scaled(62), alignment: .leading)
                    Text("Host / Path")
                    Spacer()
                    Text("Status")
                        .frame(width: DesignSystem.Metrics.scaled(54), alignment: .trailing)
                }
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .accessibilityHidden(true)

                List(selection: $selectedFlowID) {
                    ForEach(model.flows) { flow in
                        SessionFlowRow(
                            item: flow,
                            colors: colors,
                            isSelected: selectedFlowID == flow.id,
                            onEditMetadata: { onEditMetadata(flow) },
                            onToggleBookmark: { onToggleBookmark(flow) },
                            onOpen: { onOpenFlow(flow.flow) }
                        )
                        .tag(flow.id)
                    }
                }
                .listStyle(.inset)
                .tint(colors.accent)
                .scrollContentBackground(.hidden)
                .background(colors.background)

                Divider()

                HStack(spacing: DesignSystem.Spacing.md) {
                    if let selectedFlow {
                        ControlButton(title: "Open Flow", systemImage: "arrow.up.right.square", style: .ghost(colors)) {
                            onOpenFlow(selectedFlow.flow)
                        }
                        .keyboardShortcut(.return, modifiers: [])

                        ControlButton(title: selectedFlow.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text", style: .ghost(colors)) {
                            onEditMetadata(selectedFlow)
                        }

                        ControlButton(
                            title: selectedFlow.isBookmarked ? "Remove Bookmark" : "Bookmark",
                            systemImage: selectedFlow.isBookmarked ? "star.slash" : "star",
                            style: .ghost(colors)
                        ) {
                            onToggleBookmark(selectedFlow)
                        }
                        .keyboardShortcut("b", modifiers: .command)
                    } else {
                        Text("Select a flow to open it, add a note, or bookmark it.")
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.warning)
                            .lineLimit(1)
                            .help(errorMessage)
                        ControlButton(title: "Retry", systemImage: "arrow.clockwise", style: .ghost(colors), disabled: model.isLoading, action: onLoadMore)
                    } else if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading more…")
                            .foregroundStyle(colors.textSecondary)
                    } else if model.canLoadMore {
                        ControlButton(title: "Load More", systemImage: "arrow.down.circle", style: .ghost(colors), action: onLoadMore)
                    } else {
                        Text("Loaded flows: \(model.flows.count)")
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .font(DesignSystem.Fonts.caption)
                .padding(DesignSystem.Spacing.md)
            }
        }
        .background(colors.background)
        .onChange(of: session.id) {
            selectedFlowID = nil
        }
    }

    private var selectedFlow: CaptureSessionFlow? {
        guard let selectedFlowID else { return nil }
        return model.flows.first(where: { $0.id == selectedFlowID })
    }
}
