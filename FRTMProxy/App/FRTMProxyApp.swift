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
    @StateObject private var proxyViewModel: ProxyViewModel
    @StateObject private var rulesViewModel = MapRuleViewModel()
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var onboardingManager = OnboardingManager()
    @State private var deviceAlert: DeviceAlert?
    @State private var isInstallingSimulatorCertificate = false
    private let certificateInstaller = SimulatorCertificateInstaller()
    @Environment(\.openWindow) private var openWindow
    private let updaterController: SPUStandardUpdaterController
    private let launchConfiguration: LaunchConfiguration
    
    init() {
        let launchConfiguration = LaunchConfiguration.current
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)

        let proxyService: ProxyServiceProtocol
        if launchConfiguration.useMockFlows {
            proxyService = ProxyMockService()
        } else {
            switch settings.activeProxyEngine {
            case .swiftNIO:
                proxyService = NIOProxyService()
            case .mitmproxy:
                proxyService = NIOProxyService()
            }
        }

        _proxyViewModel = StateObject(wrappedValue: ProxyViewModel(service: proxyService))
        self.launchConfiguration = launchConfiguration
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
                    if launchConfiguration.autoStartProxy && !proxyViewModel.isRunning {
                        await proxyViewModel.startProxy(port: settingsStore.defaultPort)
                    }
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
                Divider()
                Toggle("Override macOS proxy", isOn: $settingsStore.overrideMacOSProxy)
            }
        }
        
        MenuBarExtra {
            ProxyMenuBarExtra(proxyViewModel: proxyViewModel)
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
}

private struct DeviceAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct LaunchConfiguration {
    let useMockFlows: Bool
    let autoStartProxy: Bool

    static var current: LaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let environment = processInfo.environment

        let useMockFlows = arguments.contains("--mock-flows")
            || boolValue(for: "FRTMPROXY_MOCK_FLOWS", in: environment) == true

        let autoStartProxy: Bool
        if arguments.contains("--mock-no-autostart") {
            autoStartProxy = false
        } else if arguments.contains("--mock-autostart") {
            autoStartProxy = true
        } else {
            autoStartProxy = boolValue(for: "FRTMPROXY_MOCK_AUTOSTART", in: environment) ?? useMockFlows
        }

        return LaunchConfiguration(useMockFlows: useMockFlows, autoStartProxy: autoStartProxy)
    }

    private static func boolValue(for key: String, in environment: [String: String]) -> Bool? {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}
