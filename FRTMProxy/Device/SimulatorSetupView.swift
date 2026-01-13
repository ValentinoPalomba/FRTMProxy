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

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let devices = try self?.installer.bootedSimulators() ?? []
                await MainActor.run {
                    self?.bootedSimulators = devices
                    self?.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self?.bootedSimulators = []
                    self?.isRefreshing = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func installCertificate() {
        guard !isInstalling else { return }
        isInstalling = true
        statusMessage = nil
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let message = try self?.installer.installCertificateOnBootedSimulators() ?? ""
                let devices = try self?.installer.bootedSimulators() ?? []
                await MainActor.run {
                    self?.bootedSimulators = devices
                    self?.isInstalling = false
                    self?.statusMessage = message.isEmpty ? "Certificate installed successfully." : message
                }
            } catch {
                await MainActor.run {
                    self?.isInstalling = false
                    self?.errorMessage = error.localizedDescription
                }
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
        VStack(alignment: .leading, spacing: 16) {
            header
            instructionList
            simulatorSection
            actionButtons
            statusSection
        }
        .padding(18)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("iOS Simulator")
                .font(DesignSystem.Fonts.mono(16, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("Install the mitmproxy certificate on booted simulators with one click.")
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var instructionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            instructionRow(1, "Launch at least one simulator from Xcode so it appears as booted.")
            instructionRow(2, "Press “Install certificate” to push the mitmproxy CA into every booted simulator.")
            instructionRow(3, "Restart the target app inside the simulator to pick up the new certificate.")
        }
    }

    private var simulatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simulators")
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)

            if model.bootedSimulators.isEmpty {
                callout("No booted simulators detected. Open Simulator/Xcode and tap “Refresh booted”.", icon: "exclamationmark.circle", tint: colors.warning)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.bootedSimulators, id: \.udid) { simulator in
                        simulatorBadge(simulator)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 8) {
            if let status = model.statusMessage {
                callout(status, icon: "checkmark.circle.fill", tint: colors.success)
            }
            if let error = model.errorMessage {
                callout(error, icon: "xmark.octagon.fill", tint: colors.danger)
            }
        }
    }

    private func instructionRow(_ step: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .font(DesignSystem.Fonts.mono(12, weight: .bold))
                .foregroundStyle(colors.accent)
                .frame(width: 24, alignment: .leading)
            Text(text)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
    }

    private func simulatorBadge(_ simulator: SimulatorCertificateInstaller.BootedSimulator) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.surfaceElevated)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "iphone")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.accentSecondary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(simulator.name)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(simulator.udid)
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func callout(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(8)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}
