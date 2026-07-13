import SwiftUI

struct FlowHeaderView: View {
    let colors: DesignSystem.ColorPalette
    let onMapLocal: (() -> Void)?
    let onCopyUrl: (() -> Void)?
    let onCopyCurl: (() -> Void)?
    let onCopyBody: (() -> Void)?
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?
    @State private var showBreakpointMenu = false

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let onMapLocal {
                    ControlButton(title: "Map Local", systemImage: "app.badge", style: .ghost(colors)) { onMapLocal() }
                        .onboardingTarget(.mapResponse)
                }
                if let toggle = onToggleBreakpoint {
                    BreakpointSelectorButton(
                        colors: colors,
                        isPresented: $showBreakpointMenu,
                        isRequestEnabled: isRequestBreakpointEnabled,
                        isResponseEnabled: isResponseBreakpointEnabled,
                        onToggle: toggle
                    )
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                            .stroke(colors.border.opacity(0.7), lineWidth: 1)
                    )
            )
        }
    }
}

private struct BreakpointSelectorButton: View {
    let colors: DesignSystem.ColorPalette
    @Binding var isPresented: Bool
    let isRequestEnabled: Bool
    let isResponseEnabled: Bool
    let onToggle: (FlowBreakpointPhase, Bool) -> Void

    private var hasBreakpointEnabled: Bool {
        isRequestEnabled || isResponseEnabled
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Breakpoint", systemImage: hasBreakpointEnabled ? "record.circle.fill" : "record.circle")
                .font(DesignSystem.Fonts.mono(13, weight: .semibold))
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .frame(minHeight: DesignSystem.Metrics.scaled(34))
                .background(hasBreakpointEnabled ? colors.accent.opacity(0.9) : colors.surface)
                .foregroundStyle(hasBreakpointEnabled ? Color.black.opacity(0.9) : colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(hasBreakpointEnabled ? colors.accent : colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Pause")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                BreakpointToggleRow(
                    title: "Request",
                    subtitle: "Pause the request before sending it",
                    isEnabled: isRequestEnabled,
                    colors: colors
                ) {
                    onToggle(.request, !isRequestEnabled)
                }
                BreakpointToggleRow(
                    title: "Response",
                    subtitle: "Pause the response before showing it",
                    isEnabled: isResponseEnabled,
                    colors: colors
                ) {
                    onToggle(.response, !isResponseEnabled)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(width: DesignSystem.Metrics.scaled(240))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
            )
        }
    }
}

private struct BreakpointToggleRow: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let colors: DesignSystem.ColorPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? colors.accent : colors.border)
                    .font(.system(size: DesignSystem.Metrics.scaled(18)))
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                            .stroke(isEnabled ? colors.accent : colors.border.opacity(0.8), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
