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
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
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
            .padding(DesignSystem.Metrics.scaled(6))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12), style: .continuous)
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
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
                .padding(.horizontal, DesignSystem.Metrics.scaled(14))
                .padding(.vertical, DesignSystem.Metrics.scaled(9))
                .frame(minHeight: DesignSystem.Metrics.scaled(34))
                .background(hasBreakpointEnabled ? colors.accent.opacity(0.9) : colors.surface)
                .foregroundStyle(hasBreakpointEnabled ? Color.black.opacity(0.9) : colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                        .stroke(hasBreakpointEnabled ? colors.accent : colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(14)) {
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
            .padding(DesignSystem.Metrics.scaled(16))
            .frame(width: DesignSystem.Metrics.scaled(240))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(16), style: .continuous)
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
            HStack(spacing: DesignSystem.Metrics.scaled(12)) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? colors.accent : colors.border)
                    .font(.system(size: DesignSystem.Metrics.scaled(18)))
                VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(2)) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(DesignSystem.Metrics.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
                            .stroke(isEnabled ? colors.accent : colors.border.opacity(0.8), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
