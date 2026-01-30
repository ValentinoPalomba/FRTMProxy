import AppKit
import SwiftUI

struct ProxyMenuBarExtra: View {
    @ObservedObject var proxyViewModel: ProxyViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            showMainWindow()
        } label: {
            Label("Open FRTMProxy", systemImage: "macwindow")
        }

        Divider()

        Button {
            Task { @MainActor in
                await proxyViewModel.startProxy()
            }
        } label: {
            Label("Start Proxy", systemImage: "play.fill")
        }
        .disabled(proxyViewModel.isRunning)

        Button {
            proxyViewModel.stopProxy()
        } label: {
            Label("Stop Proxy", systemImage: "stop.fill")
        }
        .disabled(!proxyViewModel.isRunning)

        Divider()

        Button("Quit", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
