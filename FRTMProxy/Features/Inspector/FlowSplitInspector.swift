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
            FlowMetaBar(flow: flow, colors: colors)
            FlowHeaderView(
                colors: colors,
                onMapLocal: onMapLocal,
                onCopyUrl: onCopyUrl,
                onCopyCurl: onCopyCurl,
                onCopyBody: onCopyBody,
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
        HStack(spacing: DesignSystem.Metrics.scaled(12)) {
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
            .font(DesignSystem.Fonts.mono(12))
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
                .foregroundStyle(colors.textSecondary)
            }

            if let clientLabel {
                HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                    Image(systemName: clientIcon)
                    Text(clientLabel)
                }
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                .padding(.vertical, DesignSystem.Metrics.scaled(6))
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
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                .padding(.vertical, DesignSystem.Metrics.scaled(6))
                .background(
                    Capsule().fill(colors.accent.opacity(0.12))
                )
                .foregroundStyle(colors.accent)
            }
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(14))
        .padding(.vertical, DesignSystem.Metrics.scaled(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12), style: .continuous)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12), style: .continuous)
                .stroke(colors.border.opacity(0.7), lineWidth: 1)
        )
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
