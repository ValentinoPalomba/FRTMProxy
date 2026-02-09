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
    @StateObject private var domainApprovalStore: DomainApprovalStore
    @State private var deviceAlert: DeviceAlert?
    @State private var isInstallingSimulatorCertificate = false
    @State private var isInstallingMacCertificate = false
    @State private var shouldPromptMacCertificateTrust = false
    @State private var macCertificateSHA1ForPrompt: String = ""
    private let certificateInstaller = SimulatorCertificateInstaller()
    private let macCertificateInstaller = MacCertificateInstaller()
    @Environment(\.openWindow) private var openWindow
    private let updaterController: SPUStandardUpdaterController
    private let launchConfiguration: LaunchConfiguration
    private let macCertificatePromptedSHA1Key = "settings.proxycoreMacCA.promptedSHA1"
    
    init() {
        let launchConfiguration = LaunchConfiguration.current
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)
        
        // Create domain approval store ONCE
        let domainStore = DomainApprovalStore()
        _domainApprovalStore = StateObject(wrappedValue: domainStore)

        let proxyService: ProxyServiceProtocol = launchConfiguration.useMockFlows
            ? ProxyMockService()
            : {
                let service = NIOProxyService()
                service.domainApprovalStore = domainStore  // Use SAME instance
                return service
            }()

        _proxyViewModel = StateObject(wrappedValue: ProxyViewModel(service: proxyService))
        self.launchConfiguration = launchConfiguration
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView(viewModel: proxyViewModel, rulesViewModel: rulesViewModel)
                .environmentObject(settingsStore)
                .environmentObject(onboardingManager)
                .environmentObject(domainApprovalStore)
                .preferredColorScheme(settingsStore.activeTheme.preferredColorScheme)
                .task {
                    appDelegate.proxyViewModel = proxyViewModel
                    proxyViewModel.bind(settings: settingsStore)
                    if launchConfiguration.autoStartProxy && !proxyViewModel.isRunning {
                        await proxyViewModel.startProxy(port: settingsStore.defaultPort)
                    }

                    // If the user enabled macOS proxy override, make sure the proxy CA is trusted,
                    // otherwise browsers will show TLS warnings for every intercepted HTTPS request.
                    await checkMacCertificateTrustOnLaunchIfNeeded()
                }
                .alert(item: $deviceAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .alert("Trust Proxy Certificate", isPresented: $shouldPromptMacCertificateTrust) {
                    Button("Install & Trust") {
                        shouldPromptMacCertificateTrust = false
                        installProxyCoreCertificateOnMac()
                    }
                    Button("Not now", role: .cancel) {
                        shouldPromptMacCertificateTrust = false
                    }
                } message: {
                    Text("""
                    To intercept HTTPS on this Mac, you must trust the ProxyCore Root CA.

                    SHA1: \(macCertificateSHA1ForPrompt)

                    Note: Firefox uses its own certificate store (you may need to enable enterprise roots or import the CA manually).
                    """)
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
                Button(action: installProxyCoreCertificateOnMac) {
                    Label {
                        Text(isInstallingMacCertificate ? "Installing Certificate…" : "Install proxy Certificate on Mac")
                    } icon: {
                        Image(systemName: isInstallingMacCertificate ? "hourglass" : "checkmark.shield")
                    }
                }
                .disabled(isInstallingMacCertificate)

                Button(action: installProxyCertificateOnSimulator) {
                    Label {
                        Text(isInstallingSimulatorCertificate ? "Installing Certificate…" : "Install proxy Certificate on Simulator")
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

    private func installProxyCertificateOnSimulator() {
        guard !isInstallingSimulatorCertificate else { return }
        isInstallingSimulatorCertificate = true
        let installer = certificateInstaller

        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let message = try await installer.installCertificateOnBootedSimulators()
                result = .success(message)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
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

    private func installProxyCoreCertificateOnMac() {
        guard !isInstallingMacCertificate else { return }
        isInstallingMacCertificate = true
        let installer = macCertificateInstaller

        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let message = try await installer.installTrustedRootCA()
                result = .success(message)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self.isInstallingMacCertificate = false
                switch result {
                case .success(let message):
                    self.deviceAlert = DeviceAlert(
                        title: "Operation completed",
                        message: message
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

    @MainActor
    private func checkMacCertificateTrustOnLaunchIfNeeded() async {
        guard settingsStore.overrideMacOSProxy else { return }

        do {
            let status = try await macCertificateInstaller.trustStatus()
            let defaults = UserDefaults.standard
            let previouslyPromptedSHA1 = defaults.string(forKey: macCertificatePromptedSHA1Key)

            // Avoid nagging: only prompt once per CA fingerprint.
            guard previouslyPromptedSHA1 != status.sha1Hex else { return }
            defaults.set(status.sha1Hex, forKey: macCertificatePromptedSHA1Key)

            guard !status.isTrusted else { return }

            macCertificateSHA1ForPrompt = status.sha1Hex
            shouldPromptMacCertificateTrust = true
        } catch {
            // If we can't determine status, don't block app startup.
            return
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
