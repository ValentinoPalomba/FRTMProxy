import SwiftUI

struct ThemePickerSection: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let themes: [AppTheme]
    @Binding var selection: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsCard(title: title, subtitle: subtitle, colors: colors) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(themes) { theme in
                    ThemeOptionRow(theme: theme, selection: $selection, colors: colors)
                }
            }
        }
    }
}
