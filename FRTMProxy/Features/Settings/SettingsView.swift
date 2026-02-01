import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        if #available(macOS 15.0, *) {
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
        } else {
            TabView {
                SettingsGitTab(colors: colors)
                    .tabItem {
                        Label("Git", systemImage: "arrow.triangle.branch")
                    }

                SettingsProxyTab(colors: colors)
                    .tabItem {
                        Label("Proxy", systemImage: "shield.lefthalf.filled")
                    }

                SettingsTrafficTab(colors: colors)
                    .tabItem {
                        Label("Traffic", systemImage: "speedometer")
                    }

                SettingsAlertsTab(colors: colors)
                    .tabItem {
                        Label("Alerts", systemImage: "bell.badge")
                    }

                SettingsThemesTab(colors: colors)
                    .tabItem {
                        Label("Themes", systemImage: "paintpalette")
                    }

                SettingsOnboardingTab(colors: colors)
                    .tabItem {
                        Label("Onboarding", systemImage: "sparkles")
                    }
            }
            .background(colors.background)
            .frame(minWidth: 560, minHeight: 520)
        }
    }
}
