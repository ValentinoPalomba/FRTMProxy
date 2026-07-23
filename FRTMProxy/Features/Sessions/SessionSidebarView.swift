import SwiftUI

struct SessionSidebarView: View {
    let sessions: [CaptureSession]
    @Binding var selection: UUID?
    let colors: DesignSystem.ColorPalette
    let onClose: (CaptureSession) -> Void
    let onDelete: (CaptureSession) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(sessions) { session in
                SessionSidebarRow(session: session, colors: colors)
                    .tag(session.id)
                    .contextMenu {
                        if session.isActive {
                            Button("Close Session", systemImage: "stop.circle") {
                                onClose(session)
                            }
                            Divider()
                        }
                        Button("Delete Session", systemImage: "trash", role: .destructive) {
                            onDelete(session)
                        }
                        .disabled(session.isActive)

                        if session.isActive {
                            Text("Close this session before deleting it.")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "clock",
                    description: Text("Captured sessions will appear here.")
                )
            }
        }
    }
}
