import SwiftUI

struct StatusBadge: View {
    let status: Int?
    let colors: DesignSystem.ColorPalette
    
    private var color: Color {
        guard let status else { return .gray }
        switch status {
        case 200..<300: return colors.success
        case 300..<400: return colors.accentSecondary
        case 400..<500: return colors.warning
        case 500..<600: return colors.danger
        default: return colors.textSecondary
        }
    }
    
    var body: some View {
        Text(status.map(String.init) ?? "—")
            .font(DesignSystem.Fonts.sans(12, weight: .semibold))
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
            .accessibilityLabel(status.map { "Status \($0)" } ?? "No status")
    }
}

struct StatusPill: View {
    let isRunning: Bool
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(isRunning ? colors.accent : colors.danger)
                .frame(width: DesignSystem.Metrics.scaled(9), height: DesignSystem.Metrics.scaled(9))
            Text(isRunning ? "Running" : "Offline")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            Capsule()
                .fill(colors.surfaceElevated)
        )
    }
}
