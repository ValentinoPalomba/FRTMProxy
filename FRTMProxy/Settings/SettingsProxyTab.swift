import SwiftUI

struct SettingsProxyTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Proxy",
            subtitle: "Startup behavior and system proxy integration for the embedded mitmproxy.",
            colors: colors
        ) {
            SettingsCard(title: "Behavior", colors: colors) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $settings.autoStartProxy) {
                        Text("Start proxy automatically")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                    Toggle(isOn: $settings.autoClearOnStart) {
                        Text("Clear captured flows on start")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                    Toggle(isOn: $settings.restrictInterceptionToActivePinnedHosts) {
                        Text("Intercept only active pinned hosts")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                    Toggle(isOn: $settings.overrideMacOSProxy) {
                        Text("Override macOS proxy")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                        .onboardingTarget(.macOSProxyOverride)
                }
                .toggleStyle(SwitchToggleStyle())

                Divider()
                    .overlay(colors.border.opacity(0.6))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Default port")
                            .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        TextField("", value: $settings.defaultPort, formatter: portFormatter)
                            .frame(width: 92)
                            .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                            .onChange(of: settings.defaultPort) { _, newValue in
                                settings.defaultPort = Self.sanitizedPort(newValue)
                            }
                    }

                    Text("Port used when starting the embedded mitmproxy. Range 1024–65535.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                    Text("When enabled, macOS routes HTTP and HTTPS traffic to localhost on the selected port.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                    Text("When enabled, mitmproxy only MITMs active pinned hosts; all other HTTPS traffic is tunneled. Restart the proxy to apply changes.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                }
            }

        }
    }

    private let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1024
        formatter.maximum = 65535
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func sanitizedPort(_ value: Int) -> Int {
        min(max(value, 1024), 65535)
    }
}
