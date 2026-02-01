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
                title: "Automatic",
                subtitle: "Match macOS appearance and keep the app's original colors.",
                themes: ThemeLibrary.automaticThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Light Themes",
                subtitle: "Palettes designed for bright environments.",
                themes: ThemeLibrary.lightThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Dark Themes",
                subtitle: "Ideal for night sessions or low-light environments.",
                themes: ThemeLibrary.darkThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )
        }
    }
}
