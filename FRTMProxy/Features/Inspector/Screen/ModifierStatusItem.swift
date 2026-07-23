import SwiftUI

struct ModifierStatusItem: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color
    let colors: DesignSystem.ColorPalette
    var customLabel: String? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text(customLabel ?? "\(title): \(count)")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
        )
    }
}
