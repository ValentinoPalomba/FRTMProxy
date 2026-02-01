import SwiftUI

struct SettingsTabHeader: View {
    let title: String
    let subtitle: String?
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Fonts.mono(22, weight: .bold))
                .foregroundStyle(colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Fonts.sans(13, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }
}
