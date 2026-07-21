import SwiftUI

struct SessionSidebarRow: View {
    let session: CaptureSession
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: session.isActive ? "record.circle.fill" : "clock")
                .foregroundStyle(session.isActive ? colors.danger : colors.textSecondary)
                .frame(width: DesignSystem.Metrics.scaled(16))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(session.name)
                        .lineLimit(1)
                    if session.isActive {
                        Text("ACTIVE")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(colors.danger)
                    }
                }
                Text("\(session.flowCount) flows · \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(session.flowCount) flows\(session.isActive ? ", active" : "")")
    }
}
