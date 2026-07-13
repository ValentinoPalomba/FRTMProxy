import SwiftUI

struct SettingsTabHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Fonts.titleLarge)
                .foregroundStyle(colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }
}
