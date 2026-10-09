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
                SessionSidebarRow(session: session, colors: colors, isSelected: selection == session.id)
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
        .tint(colors.accent)
        .scrollContentBackground(.hidden)
        .background(colors.surface)
        .overlay {
            if sessions.isEmpty {
                StateView(kind: .empty(title: "No Sessions", message: "Captured sessions will appear here.", systemImage: "clock"), palette: colors)
            }
        }
    }
}
