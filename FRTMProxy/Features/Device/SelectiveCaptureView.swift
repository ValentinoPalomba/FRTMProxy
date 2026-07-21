import AppKit
import SwiftUI

struct SelectiveCaptureView: View {
    private enum Target: String, CaseIterable, Identifiable {
        case application = "App / Browser"
        case command = "CLI"

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
    @State private var errorMessage: String?
    @State private var isLaunching = false
    @State private var launchedProcess: Process?

    private let service = SelectiveCaptureService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SelectiveCaptureHeader(colors: colors, onClose: onClose)

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                targetConfiguration
                targetSelection

                if target == .command {
                    commandArguments
                }
                statusMessage

                Spacer()

                HStack(spacing: DesignSystem.Spacing.md) {
                    Label("127.0.0.1:\(proxyPort)", systemImage: proxyIsRunning ? "circle.fill" : "circle")
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(proxyIsRunning ? colors.success : colors.textSecondary)
                    Spacer()
                    ControlButton(
                        title: isLaunching ? "Launching…" : "Launch",
                        systemImage: "play.fill",
                        style: .filled(colors),
                        disabled: selectedURL == nil || !proxyIsRunning || isLaunching,
                        action: launch
                    )
                }
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(colors.background)
    }

    private var targetConfiguration: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Capture target")
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(colors.textSecondary)
                Picker("Capture target", selection: $target) {
                    ForEach(Target.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: target) { _, _ in selectedURL = nil }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Launch profile")
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(colors.textSecondary)
                Picker("Launch profile", selection: $profile) {
                    Text("Standard environment").tag(CaptureLaunchProfile.standardEnvironment)
                    Text("Chromium").tag(CaptureLaunchProfile.chromium)
                    Text("Electron").tag(CaptureLaunchProfile.electron)
                }
                .labelsHidden()
                .disabled(target == .command)
            }
        }
    }

    private var targetSelection: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: target == .application ? "app.dashed" : "terminal")
                .font(.title2)
                .foregroundStyle(selectedURL == nil ? colors.textSecondary : colors.accent)
                .frame(width: DesignSystem.Metrics.scaled(32))
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(target == .application ? "Application" : "Executable")
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                Text(selectedURL?.path ?? "No target selected")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            ControlButton(
                title: "Choose…",
                systemImage: "folder",
                style: .ghost(colors),
                action: chooseTarget
            )
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(palette: colors, radius: DesignSystem.Radius.md, shadowOpacity: 0)
    }

    private var commandArguments: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Arguments")
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textSecondary)
            TextEditor(text: $arguments)
                .font(DesignSystem.Fonts.mono(12))
                .scrollContentBackground(.hidden)
                .padding(DesignSystem.Spacing.sm)
                .frame(minHeight: 100)
                .background(colors.surface)
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .strokeBorder(colors.border, lineWidth: 1)
                }
            Text("Enter one argument per line. Arguments are passed directly without a shell.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if !proxyIsRunning {
            Label("Start the proxy before launching a selective target.", systemImage: "exclamationmark.triangle.fill")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.warning)
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.warning.opacity(0.1))
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "xmark.octagon.fill")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.danger)
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.danger.opacity(0.1))
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
                .textSelection(.enabled)
        }
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
        }
    }

    private func launch() {
        guard let selectedURL else { return }
        errorMessage = nil
        isLaunching = true
        let configuration = SelectiveCaptureConfiguration(
            proxyPort: proxyPort,
            certificateURL: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".mitmproxy/mitmproxy-ca-cert.pem"),
            profile: target == .command ? .standardEnvironment : profile
        )

        switch target {
        case .application:
            Task { @MainActor in
                defer { isLaunching = false }
                do {
                    _ = try await service.launchApplication(at: selectedURL, configuration: configuration)
                    onClose()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .command:
            do {
                launchedProcess = try service.launchCommand(
                    executableURL: selectedURL,
                    arguments: arguments.split(whereSeparator: \.isNewline).map(String.init),
                    configuration: configuration
                )
                isLaunching = false
                onClose()
            } catch {
                isLaunching = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SelectiveCaptureHeader: View {
    let colors: DesignSystem.ColorPalette
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Selective Capture")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(colors.textPrimary)
                Text("Route one app, browser profile, or CLI through FRTMProxy without changing the system proxy.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors), action: onClose)
        }
        .padding(DesignSystem.Spacing.xl)
        .background(colors.surface)
    }
}
