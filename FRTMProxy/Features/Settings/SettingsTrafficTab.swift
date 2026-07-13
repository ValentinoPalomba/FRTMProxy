import SwiftUI

struct SettingsTrafficTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Traffic",
            subtitle: "Inject latency, bandwidth caps, and packet loss on intercepted traffic.",
            colors: colors
        ) {
            SettingsCard(title: "Traffic Profile", colors: colors) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Text("Simulated network")
                            .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Picker("", selection: $settings.selectedTrafficProfileID) {
                            ForEach(settings.availableTrafficProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text(settings.activeTrafficProfile.summary)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)

                    if settings.selectedTrafficProfileID == TrafficProfileLibrary.manualID {
                        manualConfigurationSection
                    }

                    Text("Switching profile while the proxy runs takes effect immediately.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private var manualConfigurationSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Divider()
                .overlay(colors.border.opacity(0.6))

            Text("Advanced manual values")
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textPrimary)

            HStack(spacing: DesignSystem.Spacing.md) {
                manualIntField("Latency (ms)", value: $settings.customTrafficLatencyMs)
                manualIntField("Jitter (ms)", value: $settings.customTrafficJitterMs)
                manualIntField("Response delay (ms)", value: $settings.customTrafficResponseDelayMs)
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                manualIntField("Download (kbps)", value: $settings.customTrafficDownstreamKbps)
                manualIntField("Upload (kbps)", value: $settings.customTrafficUpstreamKbps)
                manualDoubleField("Packet loss (%)", value: $settings.customTrafficPacketLossPercent)
            }

            Text("Example: set Response delay to 3000 to add 3 seconds to every response.")
                .font(DesignSystem.Fonts.mono(11))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func manualIntField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField("", value: value, formatter: integerFormatter)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manualDoubleField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField("", value: value, formatter: decimalFormatter)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.minimum = 0
        return formatter
    }()

    private let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimum = 0
        formatter.maximum = 100
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
