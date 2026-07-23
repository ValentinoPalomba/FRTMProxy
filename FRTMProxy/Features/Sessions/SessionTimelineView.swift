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

    @State private var selectedFlowID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionTimelineHeader(session: session, colors: colors)

            if !model.corruptFlowIDs.isEmpty {
                SessionCorruptionNotice(count: model.corruptFlowIDs.count, colors: colors)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

            if model.isLoading && !model.hasLoadedPage {
                ProgressView("Loading captured flows…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage, !model.hasLoadedPage {
                ContentUnavailableView {
                    Label("Unable to Load Session", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry", systemImage: "arrow.clockwise", action: onReload)
                        .buttonStyle(.borderedProminent)
                }
            } else if model.flows.isEmpty {
                ContentUnavailableView(
                    "No Captured Flows",
                    systemImage: "network.slash",
                    description: Text("This session does not contain any readable flows.")
                )
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
                            onEditMetadata: { onEditMetadata(flow) },
                            onToggleBookmark: { onToggleBookmark(flow) },
                            onOpen: { onOpenFlow(flow.flow) }
                        )
                        .tag(flow.id)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: DesignSystem.Spacing.md) {
                    if let selectedFlow {
                        Button("Open Flow", systemImage: "arrow.up.right.square") {
                            onOpenFlow(selectedFlow.flow)
                        }
                        .keyboardShortcut(.return, modifiers: [])

                        Button(selectedFlow.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text") {
                            onEditMetadata(selectedFlow)
                        }

                        Button(
                            selectedFlow.isBookmarked ? "Remove Bookmark" : "Bookmark",
                            systemImage: selectedFlow.isBookmarked ? "star.slash" : "star"
                        ) {
                            onToggleBookmark(selectedFlow)
                        }
                        .keyboardShortcut("b", modifiers: .command)
                    } else {
                        Text("Select a flow to open it, add a note, or bookmark it.")
                            .foregroundStyle(colors.textSecondary)
                    }

                    Spacer()

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.warning)
                            .lineLimit(1)
                            .help(errorMessage)
                        Button("Retry", systemImage: "arrow.clockwise", action: onLoadMore)
                            .disabled(model.isLoading)
                    } else if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading more…")
                            .foregroundStyle(colors.textSecondary)
                    } else if model.canLoadMore {
                        Button("Load More", systemImage: "arrow.down.circle", action: onLoadMore)
                    } else {
                        Text("\(model.flows.count) loaded")
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
