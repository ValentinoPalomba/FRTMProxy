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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Simulated network")
                            .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Picker("", selection: $settings.selectedTrafficProfileID) {
                            ForEach(TrafficProfileLibrary.presets) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text(TrafficProfileLibrary.profile(with: settings.selectedTrafficProfileID).summary)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)

                    Text("Switching profile while the proxy runs takes effect immediately.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}
