import SwiftUI

struct InspectorBottomBar: View {
    let colors: DesignSystem.ColorPalette
    let activeTrafficProfile: TrafficProfile
    let activeMapLocalCount: Int
    let activeCollectionsCount: Int
    let activeBreakpointsCount: Int
    let onClear: () -> Void

    private var hasActiveModifiers: Bool {
        activeMapLocalCount > 0 || activeCollectionsCount > 0 || activeBreakpointsCount > 0
    }

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(10)) {
            ControlButton(title: "Clear", systemImage: "trash", style: .ghost(colors), disabled: false) {
                onClear()
            }

            Spacer(minLength: DesignSystem.Metrics.scaled(12))

            HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                TrafficProfileStatusItem(
                    profile: activeTrafficProfile,
                    colors: colors
                )

                if activeMapLocalCount > 0 {
                    ModifierStatusItem(
                        title: "Map Local",
                        systemImage: "app.badge",
                        count: activeMapLocalCount,
                        tint: colors.accent,
                        colors: colors
                    )
                }

                if activeCollectionsCount > 0 {
                    ModifierStatusItem(
                        title: "Collections",
                        systemImage: "folder",
                        count: activeCollectionsCount,
                        tint: colors.accentSecondary,
                        colors: colors
                    )
                }

                if activeBreakpointsCount > 0 {
                    ModifierStatusItem(
                        title: "Breakpoints",
                        systemImage: "record.circle",
                        count: activeBreakpointsCount,
                        tint: colors.danger,
                        colors: colors
                    )
                }

                if !hasActiveModifiers {
                    Text("No active modifiers")
                        .font(DesignSystem.Fonts.sans(12, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(10))
        .padding(.vertical, DesignSystem.Metrics.scaled(4))
        .background(
            Rectangle()
                .fill(colors.surface.opacity(0.97))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(colors.border.opacity(0.9))
                        .frame(height: 1)
                }
        )
    }
}

private struct TrafficProfileStatusItem: View {
    let profile: TrafficProfile
    let colors: DesignSystem.ColorPalette

    private var tint: Color {
        profile.isDisabled ? colors.textSecondary : colors.warning
    }

    private var label: String {
        profile.isDisabled ? "Profile: Off" : "Profile: \(profile.name)"
    }

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(5)) {
            Image(systemName: profile.systemImageName)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text(label)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
        .padding(.vertical, DesignSystem.Metrics.scaled(4))
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

private struct ModifierStatusItem: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(5)) {
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text("\(title): \(count)")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
        .padding(.vertical, DesignSystem.Metrics.scaled(4))
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
