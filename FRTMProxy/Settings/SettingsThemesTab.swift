import SwiftUI

struct SettingsThemesTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Themes",
            subtitle: "Choose an appearance preset for the app UI and inspector panels.",
            colors: colors
        ) {
            ThemePickerSection(
                title: "Automatico",
                subtitle: "Usa l'aspetto di macOS e mantieni i colori originali dell'app.",
                themes: ThemeLibrary.automaticThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Temi Chiari",
                subtitle: "Palette pensate per ambienti luminosi.",
                themes: ThemeLibrary.lightThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Temi Scuri",
                subtitle: "Ideali per sessioni notturne o ambienti poco illuminati.",
                themes: ThemeLibrary.darkThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )
        }
    }
}
