import SwiftUI

struct SessionSidebarView: View {
    let sessions: [CaptureSession]
    @Binding var selection: UUID?
    let colors: DesignSystem.ColorPalette
    let onDelete: (CaptureSession) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(sessions) { session in
                SessionSidebarRow(session: session, colors: colors)
                    .tag(session.id)
                    .contextMenu {
                        Button("Delete Session", systemImage: "trash", role: .destructive) {
                            onDelete(session)
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
