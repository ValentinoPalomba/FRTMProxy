import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        TabView {
            Tab("Git", systemImage: "arrow.triangle.branch") {
                SettingsGitTab(colors: colors)
            }

            Tab("Proxy", systemImage: "shield.lefthalf.filled") {
                SettingsProxyTab(colors: colors)
            }

            Tab("Traffic", systemImage: "speedometer") {
                SettingsTrafficTab(colors: colors)
            }

            Tab("Alerts", systemImage: "bell.badge") {
                SettingsAlertsTab(colors: colors)
            }

            Tab("Themes", systemImage: "paintpalette") {
                SettingsThemesTab(colors: colors)
            }

            Tab("Onboarding", systemImage: "sparkles") {
                SettingsOnboardingTab(colors: colors)
            }
        }
        .background(colors.background)
        .frame(minWidth: 560, minHeight: 520)
    }
}
