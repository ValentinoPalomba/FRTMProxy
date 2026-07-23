import SwiftUI

struct SessionTimelineHeader: View {
    let session: CaptureSession
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(session.name)
                        .font(DesignSystem.Fonts.title)
                        .foregroundStyle(colors.textPrimary)
                    if session.isActive {
                        Label("Active", systemImage: "record.circle.fill")
                            .font(DesignSystem.Fonts.label)
                            .foregroundStyle(colors.danger)
                    }
                }
                Text("Started \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                if session.isActive {
                    Text("Close this session before deleting it.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            Text(session.flowCount, format: .number)
                .font(DesignSystem.Fonts.title)
                .foregroundStyle(colors.textPrimary)
            Text("flows")
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(colors.surface)
        .overlay(alignment: .bottom) {
            Divider().overlay(colors.border)
        }
    }
}
