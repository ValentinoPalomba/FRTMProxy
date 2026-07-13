import AppKit
import SwiftUI

struct ProxyMenuBarExtra: View {
    @ObservedObject var proxyViewModel: ProxyViewModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)

        Divider()

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

        Toggle("Route this Mac's traffic", isOn: $settings.overrideMacOSProxy)

        Divider()

        Button("Quit", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        guard proxyViewModel.isRunning else { return "Proxy stopped" }
        return "Running · port \(proxyViewModel.activePort) · \(proxyViewModel.flows.count) flows"
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
