import SwiftUI

struct TrafficProfileStatusItem: View {
    let profile: TrafficProfile
    let colors: DesignSystem.ColorPalette

    private var tint: Color {
        profile.isDisabled ? colors.textSecondary : colors.warning
    }

    private var label: String {
        profile.isDisabled ? "Profile: Off" : "Profile: \(profile.name)"
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: profile.systemImageName)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text(label)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
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
        .fixedSize(horizontal: true, vertical: false)
    }
}
