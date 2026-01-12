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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }
}

struct StatusPill: View {
    let isRunning: Bool
    let colors: DesignSystem.ColorPalette
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? colors.accent : colors.danger)
                .frame(width: 9, height: 9)
            Text(isRunning ? "In esecuzione" : "Offline")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(colors.surfaceElevated)
        )
    }
}
