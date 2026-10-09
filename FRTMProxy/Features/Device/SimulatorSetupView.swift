import SwiftUI

@MainActor
final class SimulatorSetupViewModel: ObservableObject {
    @Published private(set) var bootedSimulators: [SimulatorCertificateInstaller.BootedSimulator] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let installer = SimulatorCertificateInstaller()

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        errorMessage = nil

        let installer = installer
        Task { [weak self] in
            do {
                let devices = try await Task.detached(priority: .userInitiated) {
                    try installer.bootedSimulators()
                }.value
                self?.bootedSimulators = devices
                self?.isRefreshing = false
            } catch {
                self?.bootedSimulators = []
                self?.isRefreshing = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func installCertificate() {
        guard !isInstalling else { return }
        isInstalling = true
        statusMessage = nil
        errorMessage = nil

        let installer = installer
        Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let message = try installer.installCertificateOnBootedSimulators()
                    return (message, try installer.bootedSimulators())
                }.value
                self?.bootedSimulators = result.1
                self?.isInstalling = false
                self?.statusMessage = result.0.isEmpty ? "Certificate installed successfully." : result.0
            } catch {
                self?.isInstalling = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}

struct SimulatorSetupView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = SimulatorSetupViewModel()

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            header
            instructionList
            simulatorSection
            actionButtons
            statusSection
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("iOS Simulator")
                .font(DesignSystem.Fonts.heading)
                .foregroundStyle(colors.textPrimary)
            Text("Install the mitmproxy certificate on booted simulators with one click.")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var instructionList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            instructionRow(1, "Launch at least one simulator from Xcode so it appears as booted.")
            instructionRow(2, "Press “Install certificate” to push the mitmproxy CA into every booted simulator.")
            instructionRow(3, "Restart the target app inside the simulator to pick up the new certificate.")
        }
    }

    private var simulatorSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Simulators")
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textSecondary)

            if model.isRefreshing {
                StateView(kind: .loading(message: "Finding booted simulators…"), palette: colors)
            } else if model.bootedSimulators.isEmpty {
                StateView(kind: .empty(title: "No booted simulators", message: "Open a simulator in Xcode, then refresh the list.", systemImage: "macwindow"), palette: colors)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        ForEach(model.bootedSimulators, id: \.udid) { simulator in
                            simulatorBadge(simulator)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: DesignSystem.Metrics.scaled(200))
            }
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(
                    title: model.isRefreshing ? "Refreshing…" : "Refresh booted",
                    systemImage: "arrow.clockwise",
                    style: .ghost(colors),
                    disabled: model.isRefreshing
                ) {
                    model.refresh()
                }

                ControlButton(
                    title: model.isInstalling ? "Installing…" : "Install certificate",
                    systemImage: "checkmark.shield",
                    style: .filled(colors),
                    disabled: model.isInstalling || model.bootedSimulators.isEmpty
                ) {
                    model.installCertificate()
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let status = model.statusMessage {
                callout(status, icon: "checkmark.circle.fill", tint: colors.success)
            }
            if let error = model.errorMessage {
                callout(error, icon: "xmark.octagon.fill", tint: colors.danger)
            }
        }
    }

    private func instructionRow(_ step: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Text("\(step).")
                .font(DesignSystem.Fonts.monoBody)
                .foregroundStyle(colors.accent)
                .frame(width: DesignSystem.Metrics.scaled(24), alignment: .leading)
            Text(text)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textPrimary)
        }
    }

    private func simulatorBadge(_ simulator: SimulatorCertificateInstaller.BootedSimulator) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(colors.surfaceElevated)
                .frame(width: DesignSystem.Metrics.scaled(42), height: DesignSystem.Metrics.scaled(42))
                .overlay(
                    Image(systemName: "iphone")
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.accentSecondary)
                )
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(simulator.name)
                    .lineLimit(2)
                    .help(simulator.name)
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(colors.textPrimary)
                Text(simulator.udid)
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(simulator.udid)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private func callout(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(tint)
                .padding(DesignSystem.Spacing.sm)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
            Text(text)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textPrimary)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}
