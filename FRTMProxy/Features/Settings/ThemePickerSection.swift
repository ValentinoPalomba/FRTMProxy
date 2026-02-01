import SwiftUI

struct ThemePickerSection: View {
    let title: String
    let subtitle: String
    let themes: [AppTheme]
    @Binding var selection: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsCard(title: title, subtitle: subtitle, colors: colors) {
            VStack(spacing: 10) {
                ForEach(themes) { theme in
                    ThemeOptionRow(theme: theme, selection: $selection, colors: colors)
                }
            }
        }
    }
}
