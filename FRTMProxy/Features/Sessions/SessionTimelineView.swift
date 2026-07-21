import SwiftUI

struct SessionTimelineView: View {
    let session: CaptureSession
    let model: SessionTimelineModel
    let colors: DesignSystem.ColorPalette
    let onLoadMore: () -> Void
    let onEditMetadata: (CaptureSessionFlow) -> Void
    let onToggleBookmark: (CaptureSessionFlow) -> Void
    let onOpenFlow: (MitmFlow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            SessionTimelineHeader(session: session, colors: colors)

            if !model.corruptFlowIDs.isEmpty {
                SessionCorruptionNotice(count: model.corruptFlowIDs.count, colors: colors)
            }

            if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Unable to Load Session",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if model.isLoading && !model.hasLoadedPage {
                ProgressView("Loading captured flows…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.flows.isEmpty {
                ContentUnavailableView(
                    "No Captured Flows",
                    systemImage: "network.slash",
                    description: Text("This session does not contain any readable flows.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(model.flows) { flow in
                            SessionFlowRow(
                                item: flow,
                                colors: colors,
                                onEditMetadata: { onEditMetadata(flow) },
                                onToggleBookmark: { onToggleBookmark(flow) },
                                onOpen: { onOpenFlow(flow.flow) }
                            )
                        }

                        if model.canLoadMore || model.isLoading {
                            Button("Load More", systemImage: "arrow.down.circle") {
                                onLoadMore()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isLoading)
                            .padding(.vertical, DesignSystem.Spacing.md)
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
        }
        .background(colors.background)
    }
}
