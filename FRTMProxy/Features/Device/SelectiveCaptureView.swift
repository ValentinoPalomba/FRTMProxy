import AppKit
import SwiftUI

struct SelectiveCaptureView: View {
    private enum Target: String, CaseIterable, Identifiable {
        case application = "App or browser"
        case command = "Command line tool"

        var id: Self { self }
    }

    let proxyPort: Int
    let proxyIsRunning: Bool
    let colors: DesignSystem.ColorPalette
    let onClose: () -> Void

    @State private var target: Target = .application
    @State private var selectedURL: URL?
    @State private var profile: CaptureLaunchProfile = .standardEnvironment
    @State private var arguments = ""
    @State private var launchModel: SelectiveCaptureLaunchModel

    @MainActor
    init(
        proxyPort: Int,
        proxyIsRunning: Bool,
        colors: DesignSystem.ColorPalette,
        onClose: @escaping () -> Void
    ) {
        self.init(
            proxyPort: proxyPort,
            proxyIsRunning: proxyIsRunning,
            colors: colors,
            launcher: SelectiveCaptureService(),
            onClose: onClose
        )
    }

    @MainActor
    init(
        proxyPort: Int,
        proxyIsRunning: Bool,
        colors: DesignSystem.ColorPalette,
        launcher: any SelectiveCaptureLaunching,
        onClose: @escaping () -> Void
    ) {
        self.proxyPort = proxyPort
        self.proxyIsRunning = proxyIsRunning
        self.colors = colors
        self.onClose = onClose
        _launchModel = State(initialValue: SelectiveCaptureLaunchModel(launcher: launcher))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Selective Capture")
                        .font(DesignSystem.Fonts.title)
                        .foregroundStyle(colors.textPrimary)
                    Text("Launch one target through FRTMProxy without changing the system proxy.")
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Button("Close", systemImage: "xmark", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Closes this window without stopping a launched target.")
            }
            .padding()
            .background(colors.surface)

            Divider()

            Form {
                Section("Target") {
                    Picker("Type", selection: $target) {
                        ForEach(Target.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(launchModel.isActive)
                    .onChange(of: target) {
                        selectedURL = nil
                        launchModel.resetStatus()
                    }

                    LabeledContent(target == .application ? "Application" : "Executable") {
                        HStack {
                            Text(selectedURL?.path ?? "No target selected")
                                .foregroundStyle(selectedURL == nil ? colors.textSecondary : colors.textPrimary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button("Choose…", systemImage: "folder", action: chooseTarget)
                                .disabled(launchModel.isActive)
                        }
                    }

                    if let targetValidationMessage {
                        Label(targetValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(colors.danger)
                    }
                }

                if target == .application {
                    Section("Launch profile") {
                        Picker("Profile", selection: $profile) {
                            Text("Standard environment").tag(CaptureLaunchProfile.standardEnvironment)
                            Text("Chromium").tag(CaptureLaunchProfile.chromium)
                            Text("Electron").tag(CaptureLaunchProfile.electron)
                        }
                        .disabled(launchModel.isActive)

                        if profile == .chromium || profile == .electron {
                            Text("Uses a temporary browser profile that is removed after the launched app exits.")
                                .font(DesignSystem.Fonts.caption)
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }

                if target == .command {
                    Section("Arguments") {
                        TextEditor(text: $arguments)
                            .font(DesignSystem.Fonts.mono(12))
                            .frame(minHeight: 90)
                            .disabled(launchModel.isActive)
                        Text("Enter one argument per line. Arguments are passed directly without a shell.")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                }

                Section("Status") {
                    if !proxyIsRunning {
                        Label(
                            "Start the proxy before launching a selective target.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(colors.warning)
                    } else {
                        Label(
                            "Proxy ready at 127.0.0.1:\(proxyPort)",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(colors.success)
                    }

                    switch launchModel.state {
                    case .idle:
                        Text("Choose a target, then launch it with the proxy environment.")
                            .foregroundStyle(colors.textSecondary)
                    case .launching:
                        Label("Launching target…", systemImage: "hourglass")
                            .foregroundStyle(colors.accent)
                    case let .running(displayName):
                        Label("\(displayName) is running through FRTMProxy.", systemImage: "play.circle.fill")
                            .foregroundStyle(colors.success)
                    case let .failed(message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(colors.danger)
                            .textSelection(.enabled)
                    case let .terminated(displayName, exitCode):
                        if let exitCode {
                            Label(
                                "\(displayName) exited with status \(exitCode).",
                                systemImage: exitCode == 0 ? "checkmark.circle" : "exclamationmark.circle"
                            )
                            .foregroundStyle(exitCode == 0 ? colors.textSecondary : colors.warning)
                        } else {
                            Label("\(displayName) has exited.", systemImage: "stop.circle")
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Text("The launched target keeps running if you close this window.")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button("Launch", systemImage: "play.fill", action: launch)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLaunch)
                    .accessibilityHint("Launches the selected target using the current FRTMProxy connection.")
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 500)
        .background(colors.background)
    }

    private var targetValidationMessage: String? {
        guard let selectedURL else { return nil }

        do {
            switch target {
            case .application:
                try SelectiveCaptureError.validateApplication(at: selectedURL)
            case .command:
                try SelectiveCaptureError.validateExecutable(at: selectedURL)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canLaunch: Bool {
        selectedURL != nil
            && targetValidationMessage == nil
            && proxyIsRunning
            && !launchModel.isActive
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = target == .application
        panel.canChooseFiles = target == .command
        panel.resolvesAliases = true
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            selectedURL = panel.url
            launchModel.resetStatus()
        }
    }

    private func launch() {
        guard let selectedURL, canLaunch else { return }

        let configuration = SelectiveCaptureConfiguration(
            proxyPort: proxyPort,
            certificateURL: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".mitmproxy/mitmproxy-ca-cert.pem"),
            profile: target == .command ? .standardEnvironment : profile
        )

        switch target {
        case .application:
            Task {
                await launchModel.launchApplication(
                    at: selectedURL,
                    configuration: configuration
                )
            }
        case .command:
            launchModel.launchCommand(
                executableURL: selectedURL,
                arguments: arguments.split(whereSeparator: \.isNewline).map(String.init),
                configuration: configuration
            )
        }
    }
}
