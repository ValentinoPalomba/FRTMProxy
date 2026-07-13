import SwiftUI

struct ThemePreviewSwatches: View {
    let swatches: [Color]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            ForEach(swatches.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.scaled(4), style: .continuous)
                    .fill(swatches[index])
                    .frame(width: DesignSystem.Metrics.scaled(16), height: DesignSystem.Metrics.scaled(28))
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .surfaceCard(
            radius: DesignSystem.Radius.md,
            fill: colors.surface,
            stroke: colors.border,
            shadowOpacity: 0
        )
    }
}
