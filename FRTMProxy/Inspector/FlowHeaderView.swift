import SwiftUI

struct FlowHeaderView: View {
    let flow: MitmFlow
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let fullURL = flow.request?.url, !fullURL.isEmpty {
                        Text(fullURL)
                            .font(DesignSystem.Fonts.mono(12))
                            .foregroundStyle(colors.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(flow.host + flow.path)
                            .font(DesignSystem.Fonts.mono(12))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !flow.formattedTimestamp.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(flow.formattedTimestamp)
                    }
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                }

                if !flow.clientIP.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                        Text(flow.clientIP)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(colors.surfaceElevated)
                    )
                    .foregroundStyle(colors.textSecondary)
                }

                if flow.isMapped {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                        Text("Mapped")
                    }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                        Capsule().fill(colors.accent.opacity(0.12))
                    )
                    .foregroundStyle(colors.accent)
                }

                HStack(spacing: 8) {
                    ControlButton(title: "URL", systemImage: "link", style: .ghost(colors), disabled: onCopyUrl == nil) { onCopyUrl?() }
                    ControlButton(title: "cURL", systemImage: "terminal", style: .ghost(colors), disabled: onCopyCurl == nil) { onCopyCurl?() }
                    ControlButton(title: "Body", systemImage: "doc.on.doc", style: .ghost(colors), disabled: onCopyBody == nil) { onCopyBody?() }
                    if let onMapLocal {
                        ControlButton(title: "Map Local", systemImage: "pencil.and.outline", style: .filled(colors)) { onMapLocal() }
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
            }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 34)
                .background(hasBreakpointEnabled ? colors.accent.opacity(0.9) : colors.surface)
                .foregroundStyle(hasBreakpointEnabled ? Color.black.opacity(0.9) : colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(hasBreakpointEnabled ? colors.accent : colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Interrompi")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                BreakpointToggleRow(
                    title: "Request",
                    subtitle: "Blocca la richiesta prima di inviarla",
                    isEnabled: isRequestEnabled,
                    colors: colors
                ) {
                    onToggle(.request, !isRequestEnabled)
                }
                BreakpointToggleRow(
                    title: "Response",
                    subtitle: "Blocca la risposta prima di mostrarla",
                    isEnabled: isResponseEnabled,
                    colors: colors
                ) {
                    onToggle(.response, !isResponseEnabled)
                }
            }
            .padding(16)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            HStack(spacing: 12) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? colors.accent : colors.border)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isEnabled ? colors.accent : colors.border.opacity(0.8), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
