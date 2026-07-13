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
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? colors.accent : colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(isSelected ? colors.accent.opacity(0.12) : colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .stroke(isSelected ? colors.accent.opacity(0.6) : colors.border.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
