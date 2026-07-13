import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let colors: DesignSystem.ColorPalette
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        colors: DesignSystem.ColorPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(DesignSystem.Fonts.mono(16, weight: .bold))
                    .foregroundStyle(colors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(12, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            content
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
    }
}
