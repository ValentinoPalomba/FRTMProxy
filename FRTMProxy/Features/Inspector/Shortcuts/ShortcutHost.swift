import SwiftUI

struct ShortcutHost: View {
    let isRunning: Bool
    let hasSelection: Bool
    let onToggleProxy: () -> Void
    let onClear: () -> Void
    let onOpenCommandPalette: () -> Void
    let onMapLocal: () -> Void
    let onRetry: () -> Void
    let onCopyUrl: () -> Void
    let onCopyCurl: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button("", action: onOpenCommandPalette)
                .keyboardShortcut("k", modifiers: [.command])
            Button("", action: onToggleProxy)
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("", action: onClear)
                .keyboardShortcut("k", modifiers: [.command, .option])
            Button("", action: { if hasSelection { onMapLocal() } })
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("", action: { if hasSelection { onRetry() } })
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("", action: { if hasSelection { onCopyUrl() } })
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("", action: { if hasSelection { onCopyCurl() } })
                .keyboardShortcut("y", modifiers: [.command, .option])
        }
        .frame(width: 0, height: 0)
        .opacity(0.01)
        .disabled(false)
    }
}
