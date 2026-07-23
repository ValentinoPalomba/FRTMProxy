import SwiftUI

struct SettingsGeneralTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "General",
            subtitle: "Choose the language used throughout FRTMProxy.",
            colors: colors
        ) {
            SettingsCard(
                title: "Language",
                subtitle: "Changes are applied immediately.",
                colors: colors
            ) {
                Picker("App language", selection: $settings.selectedLanguageID) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.autonym)
                            .tag(language.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .leading)

                Text("Some system-owned dialogs follow the macOS language and may require reopening.")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }
}
