//
//  FRTMProxyApp.swift
//  FRTMProxy
//
//  Created by PALOMBA VALENTINO on 17/11/25.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var proxyViewModel: ProxyViewModel?

    func applicationWillTerminate(_ notification: Notification) {
        proxyViewModel?.stopProxy()
    }
}

@main
struct FRTMProxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var proxyViewModel = ProxyViewModel()
    @StateObject private var rulesViewModel = MapRuleViewModel()
    @StateObject private var settingsStore = SettingsStore()
    @State private var deviceAlert: DeviceAlert?
    @State private var isInstallingSimulatorCertificate = false
    private let certificateInstaller = SimulatorCertificateInstaller()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: proxyViewModel, rulesViewModel: rulesViewModel)
                .environmentObject(settingsStore)
                .preferredColorScheme(settingsStore.activeTheme.preferredColorScheme)
                .task {
                    appDelegate.proxyViewModel = proxyViewModel
                    proxyViewModel.bind(settings: settingsStore)
                }
                .alert(item: $deviceAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FRTMTools") {
                    openWindow(id: "about-ftrmtools")
                }
                .presentedWindowStyle(.hiddenTitleBar)
            }
            CommandGroup(replacing: .help) {
                Button("Find in Editor") {
                    CodeMirrorShortcutCenter.shared.focusSearchInActiveEditor()
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("Device") {
                Button(action: installMitmproxyCertificateOnSimulator) {
                    Label {
                        Text(isInstallingSimulatorCertificate ? "Installing Certificate…" : "Install mitmproxy Certificate on Simulator")
                    } icon: {
                        Image(systemName: isInstallingSimulatorCertificate ? "hourglass" : "iphone.badge.checkmark")
                    }
                }
                .disabled(isInstallingSimulatorCertificate)
            }
        }
        
        
        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .frame(minWidth: 480, maxWidth: 1280, minHeight: 480, maxHeight: 720)
        }
        
        Window("About FRTMTools", id: "about-ftrmtools") {
            AboutFRTMToolsView()
                .environmentObject(settingsStore)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
    }

    private func installMitmproxyCertificateOnSimulator() {
        guard !isInstallingSimulatorCertificate else { return }
        isInstallingSimulatorCertificate = true
        let installer = certificateInstaller

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                let message = try installer.installCertificateOnBootedSimulators()
                result = .success(message)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.isInstallingSimulatorCertificate = false
                switch result {
                case .success(let message):
                    self.deviceAlert = DeviceAlert(
                        title: "Operazione completata",
                        message: message + "\nRiavvia l'app nel simulatore per applicare la nuova CA."
                    )
                case .failure(let error):
                    self.deviceAlert = DeviceAlert(
                        title: "Installazione fallita",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}

private struct DeviceAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
