import SwiftUI
import Foundation

struct FlowSplitInspector: View {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onMapLocal: (() -> Void)?
    let onCopyUrl: (() -> Void)?
    let onCopyCurl: (() -> Void)?
    let onCopyBody: (() -> Void)?
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
            FlowMetaBar(
                flow: flow,
                colors: colors,
                onMapLocal: onMapLocal,
                isRequestBreakpointEnabled: isRequestBreakpointEnabled,
                isResponseBreakpointEnabled: isResponseBreakpointEnabled,
                onToggleBreakpoint: onToggleBreakpoint
            )

            HStack(spacing: DesignSystem.Metrics.scaled(16)) {
                FlowPanel(
                    title: "Request",
                    method: flow.request?.method,
                    status: nil,
                    headers: flow.request?.headers ?? [:],
                    queryParameters: queryParameters(in: flow.request?.url),
                    bodyFlow: flow.request?.body,
                    emptyText: "Request non disponibile",
                    isMapped: false,
                    showsParserSelector: false,
                    colors: colors
                )
                .id("\(flow.id)-request")
                .frame(maxWidth: .infinity)

                FlowPanel(
                    title: "Response",
                    method: nil,
                    status: flow.response?.status,
                    headers: flow.response?.headers ?? [:],
                    queryParameters: [],
                    bodyFlow: flow.response?.body,
                    emptyText: "Response non disponibile",
                    isMapped: flow.isMapped,
                    showsParserSelector: true,
                    colors: colors
                )
                .id("\(flow.id)-response")
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FlowMetaBar: View {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onMapLocal: (() -> Void)?
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?
    @State private var showBreakpointMenu = false

    private var clientLabel: String? {
        let appName = flow.clientApp?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !appName.isEmpty { return appName }
        let ip = flow.clientIP
        return ip.isEmpty ? nil : ip
    }

    private var clientIcon: String {
        let appName = flow.clientApp?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return appName.isEmpty ? "iphone" : "app.badge"
    }

    private var styledURLText: Text? {
        guard
            let urlString = flow.request?.url,
            let url = URL(string: urlString)
        else { return nil }

        var attributed = AttributedString(urlString)

        if let host = url.host,
           let range = attributed.range(of: host) {
            attributed[range].foregroundColor = colors.accent
        }

        if !url.path.isEmpty,
           let range = attributed.range(of: url.path) {
            attributed[range].foregroundColor = colors.success
        }

        return Text(attributed)
    }

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(10)) {
            Group {
                if let text = styledURLText {
                    text
                } else {
                    (
                        Text(flow.host)
                            .foregroundStyle(colors.accent)
                        +
                        Text(flow.path)
                            .foregroundStyle(colors.success)
                    )
                }
            }
            .font(DesignSystem.Fonts.mono(11))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)

            if !flow.formattedTimestamp.isEmpty {
                HStack(spacing: DesignSystem.Metrics.scaled(4)) {
                    Image(systemName: "clock")
                    Text(flow.formattedTimestamp)
                }
                .font(DesignSystem.Fonts.mono(11))
                .monospacedDigit()
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }

            if let clientLabel {
                HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                    Image(systemName: clientIcon)
                    Text(clientLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(DesignSystem.Fonts.sans(10, weight: .semibold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                .padding(.vertical, DesignSystem.Metrics.scaled(4))
                .background(
                    Capsule().fill(colors.surface)
                )
                .foregroundStyle(colors.textSecondary)
            }

            if flow.isMapped {
                HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                    Image(systemName: "pencil.and.outline")
                    Text("Mapped")
                }
                .font(DesignSystem.Fonts.sans(10, weight: .semibold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                .padding(.vertical, DesignSystem.Metrics.scaled(4))
                .background(
                    Capsule().fill(colors.accent.opacity(0.12))
                )
                .foregroundStyle(colors.accent)
            }

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
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(12))
        .padding(.vertical, DesignSystem.Metrics.scaled(6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10), style: .continuous)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10), style: .continuous)
                .stroke(colors.border.opacity(0.7), lineWidth: 1)
        )
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
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                Image(systemName: hasBreakpointEnabled ? "record.circle.fill" : "record.circle")
                Text("Breakpoint")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
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

private func queryParameters(in urlString: String?) -> [(String, String)] {
    guard
        let urlString,
        let components = URLComponents(string: urlString),
        let items = components.queryItems
    else {
        return []
    }
    return items.map { ($0.name, $0.value ?? "") }
}
