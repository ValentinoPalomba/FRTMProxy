import SwiftUI

struct InspectorBottomBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
    let activePort: Int
    let totalFlowCount: Int
    let shownFlowCount: Int
    let isMacProxyActive: Bool
    let activeTrafficProfile: TrafficProfile
    let activeMapLocalCount: Int
    let activeCollectionsCount: Int
    let activeBreakpointsCount: Int
    let compareFlowID: String?
    let onClear: () -> Void
    let onOpenCommandPalette: () -> Void
    let onMapLocalTap: () -> Void
    let onCollectionsTap: () -> Void
    let onBreakpointsTap: () -> Void
    let onClearCompare: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            statusSection

            Spacer(minLength: DesignSystem.Spacing.md)

            modifiersSection

            actionsSection
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xs)
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

    private var statusSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                statusDot
                Text(isRunning ? "Running :\(String(activePort))" : "Stopped")
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(isRunning ? colors.textPrimary : colors.textSecondary)
            }
            .help(statusHelp)

            statusDivider

            Text(flowCountText)
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textSecondary)
                .help("\(totalFlowCount) captured · \(shownFlowCount) shown with current filters")
        }
        .fixedSize()
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(isRunning ? colors.success : colors.textSecondary.opacity(0.5))
                .frame(width: DesignSystem.Metrics.scaled(8), height: DesignSystem.Metrics.scaled(8))
        }
        .frame(width: DesignSystem.Metrics.scaled(16), height: DesignSystem.Metrics.scaled(16))
    }

    private var statusHelp: String {
        var text = isRunning ? "Proxy listening on port \(String(activePort))" : "Proxy stopped"
        if isMacProxyActive {
            text += " · Also routing this Mac"
        }
        return text
    }

    private var flowCountText: String {
        shownFlowCount == totalFlowCount ? "\(totalFlowCount) flows" : "\(shownFlowCount) / \(totalFlowCount) flows"
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(colors.border)
            .frame(width: 1, height: DesignSystem.Metrics.scaled(12))
    }

    @ViewBuilder
    private var modifiersSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TrafficProfileStatusItem(profile: activeTrafficProfile, colors: colors)

            if activeMapLocalCount > 0 {
                ModifierStatusButton(
                    title: "Map Local",
                    systemImage: "app.badge",
                    count: activeMapLocalCount,
                    tint: colors.accent,
                    colors: colors,
                    help: "Open Map Local rules",
                    action: onMapLocalTap
                )
            }
            if activeCollectionsCount > 0 {
                ModifierStatusButton(
                    title: "Collections",
                    systemImage: "folder",
                    count: activeCollectionsCount,
                    tint: colors.accentSecondary,
                    colors: colors,
                    help: "Open Collections",
                    action: onCollectionsTap
                )
            }
            if activeBreakpointsCount > 0 {
                ModifierStatusButton(
                    title: "Breakpoints",
                    systemImage: "record.circle",
                    count: activeBreakpointsCount,
                    tint: colors.danger,
                    colors: colors,
                    help: "Open Breakpoints",
                    action: onBreakpointsTap
                )
            }
            if compareFlowID != nil {
                ModifierStatusButton(
                    title: "Compare",
                    systemImage: "square.on.square",
                    count: 0,
                    tint: colors.accentSecondary,
                    colors: colors,
                    customLabel: "Compare: active",
                    help: "Exit compare mode",
                    action: onClearCompare
                )
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ControlButton(title: "Clear", systemImage: "trash", style: .ghost(colors), disabled: totalFlowCount == 0) {
                onClear()
            }
            commandPaletteButton
        }
    }

    private var commandPaletteButton: some View {
        Button(action: onOpenCommandPalette) {
            Image(systemName: "keyboard")
                .font(.system(size: DesignSystem.Metrics.scaled(13), weight: .semibold))
                .frame(width: DesignSystem.Metrics.scaled(34), height: DesignSystem.Metrics.scaled(34))
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .foregroundStyle(colors.textPrimary)
        }
        .buttonStyle(.plain)
        .help("Command Palette (⌘K)")
        .accessibilityLabel(Text("Command Palette"))
    }
}
