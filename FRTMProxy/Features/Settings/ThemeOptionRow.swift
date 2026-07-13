import SwiftUI

struct ThemeOptionRow: View {
    let theme: AppTheme
    @Binding var selection: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        let isSelected = selection == theme.id

        Button {
            selection = theme.id
        } label: {
            HStack(spacing: DesignSystem.Spacing.lg) {
                ThemePreviewSwatches(swatches: theme.previewSwatches, colors: colors)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(theme.name)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(theme.description)
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DesignSystem.Fonts.sans(18, weight: .semibold))
                    .foregroundStyle(isSelected ? colors.accent : colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .hoverHighlight(colors, cornerRadius: DesignSystem.Radius.lg)
            .surfaceCard(
                fill: isSelected ? colors.accent.opacity(0.12) : colors.surfaceElevated,
                stroke: isSelected ? colors.accent.opacity(0.6) : colors.border,
                shadowOpacity: 0
            )
        }
        .buttonStyle(.pressable)
    }
}
