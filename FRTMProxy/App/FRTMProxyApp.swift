//
//  FRTMProxyApp.swift
//  FRTMProxy
//
//  Created by PALOMBA VALENTINO on 17/11/25.
//

import SwiftUI
import AppKit
import Sparkle

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
    @StateObject private var onboardingManager = OnboardingManager()
    @State private var deviceAlert: DeviceAlert?
    @State private var isInstallingSimulatorCertificate = false
    @State private var isInstallingMacCertificate = false
    @State private var isInstallingAndroidCertificate = false
    private let certificateInstaller = SimulatorCertificateInstaller()
    @Environment(\.openWindow) private var openWindow
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: proxyViewModel, rulesViewModel: rulesViewModel)
                .environmentObject(settingsStore)
                .environmentObject(onboardingManager)
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
            InspectorCommandsMenu()
            CommandGroup(after: .appTermination) {
                            CheckForUpdatesView(updater: updaterController.updater)
                        }
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

                Button(action: installMitmproxyCertificateOnAndroid) {
                    Label {
                        Text(isInstallingAndroidCertificate ? "Installing Certificate…" : "Install mitmproxy Certificate on Android Emulators")
                    } icon: {
                        Image(systemName: isInstallingAndroidCertificate ? "hourglass" : "cpu")
                    }
                }
                .disabled(isInstallingAndroidCertificate)

                Button(action: installMitmproxyCertificateOnMac) {
                    Label {
                        Text(isInstallingMacCertificate ? "Trusting Certificate…" : "Trust mitmproxy Certificate on this Mac")
                    } icon: {
                        Image(systemName: isInstallingMacCertificate ? "hourglass" : "checkmark.seal")
                    }
                }
                .disabled(isInstallingMacCertificate)

                Divider()

                Button("Copy CLI Proxy Environment Variables") {
                    copyProxyEnvironmentVariables()
                }

                Divider()
                Toggle("Override macOS proxy", isOn: $settingsStore.overrideMacOSProxy)
            }
        }
        
        MenuBarExtra {
            ProxyMenuBarExtra(proxyViewModel: proxyViewModel, settings: settingsStore)
        } label: {
            ProxyMenuBarLabel(isRunning: proxyViewModel.isRunning)
        }
        
        
        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(onboardingManager)
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
                        title: "Operation completed",
                        message: message + "\nRestart the app in the simulator to apply the new CA."
                    )
                case .failure(let error):
                    self.deviceAlert = DeviceAlert(
                        title: "Installation failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func installMitmproxyCertificateOnMac() {
        guard !isInstallingMacCertificate else { return }
        isInstallingMacCertificate = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                result = .success(try MacCertificateInstaller().install())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.isInstallingMacCertificate = false
                switch result {
                case .success(let message):
                    self.deviceAlert = DeviceAlert(title: "macOS certificate trusted", message: message)
                case .failure(let error):
                    self.deviceAlert = DeviceAlert(title: "Trust failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func installMitmproxyCertificateOnAndroid() {
        guard !isInstallingAndroidCertificate else { return }
        isInstallingAndroidCertificate = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                result = .success(try AndroidCertificateInstaller().installOnEmulators())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.isInstallingAndroidCertificate = false
                switch result {
                case .success(let message):
                    self.deviceAlert = DeviceAlert(title: "Android emulators", message: message)
                case .failure(let error):
                    self.deviceAlert = DeviceAlert(title: "Installation failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func copyProxyEnvironmentVariables() {
        let port = proxyViewModel.activePort
        let text = """
        export HTTP_PROXY=http://127.0.0.1:\(port)
        export HTTPS_PROXY=http://127.0.0.1:\(port)
        export SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem
        export NODE_EXTRA_CA_CERTS=$HOME/.mitmproxy/mitmproxy-ca-cert.pem
        """
        ClipboardHelper.copy(text)
        deviceAlert = DeviceAlert(
            title: "Copied",
            message: "Proxy environment variables copied. Paste them into the terminal session whose CLI traffic you want to capture, then run your command."
        )
    }
}

private struct DeviceAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
