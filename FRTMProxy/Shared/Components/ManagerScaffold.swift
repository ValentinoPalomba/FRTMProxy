import SwiftUI

struct ManagerHeaderBar<Actions: View>: View {
    let title: String
    let subtitle: String
    let colors: DesignSystem.ColorPalette
    let actions: Actions

    init(
        title: String,
        subtitle: String,
        colors: DesignSystem.ColorPalette,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.sans(21, weight: .semibold))
                Text(subtitle)
                    .font(DesignSystem.Fonts.sans(13, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                actions
            }
        }
    }
}

struct ManagerListSurface<Content: View>: View {
    let colors: DesignSystem.ColorPalette
    let content: Content

    init(colors: DesignSystem.ColorPalette, @ViewBuilder content: () -> Content) {
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.border.opacity(0.7), lineWidth: 1)
                    )
            )
    }
}

struct ManagerDeleteButton: View {
    let colors: DesignSystem.ColorPalette
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .foregroundStyle(colors.danger)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }
}
