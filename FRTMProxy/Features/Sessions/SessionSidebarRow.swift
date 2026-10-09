import SwiftUI

struct SessionSidebarRow: View {
    let session: CaptureSession
    let colors: DesignSystem.ColorPalette
    var isSelected = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: session.isActive ? "record.circle.fill" : "clock")
                .foregroundStyle(session.isActive ? colors.danger : (isSelected ? .white : colors.textSecondary))
                .frame(width: DesignSystem.Metrics.scaled(16))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(session.name)
                        .font(DesignSystem.Fonts.label)
                        .foregroundStyle(isSelected ? .white : colors.textPrimary)
                        .lineLimit(1)
                        .help(session.name)
                    if session.isActive {
                        Text("ACTIVE")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(isSelected ? .white : colors.danger)
                    }
                    if session.incompleteReason != nil {
                        Label("INCOMPLETE", systemImage: "exclamationmark.triangle")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(isSelected ? .white : colors.warning)
                    }
                }
                Text("\(session.flowCount) flows · \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(session.flowCount) flows\(session.isActive ? ", active" : "")\(session.incompleteReason == nil ? "" : ", incomplete")")
    }
}
