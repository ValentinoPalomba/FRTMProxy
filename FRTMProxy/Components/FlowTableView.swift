import AppKit
import SwiftUI

struct FlowTableView: View {
    let flows: [MitmFlow]
    @Binding var selection: String?
    let emptyMessage: String
    let colors: DesignSystem.ColorPalette
    let pinnedHostnames: Set<String>
    let pinnedAppIDs: Set<String>
    let onMapLocal: (MitmFlow) -> Void
    let onEditRetry: (MitmFlow) -> Void
    let onPinHost: (String) -> Void
    let onUnpinHost: (String) -> Void
    let onPinApp: (FlowClientApp) -> Void
    let onUnpinApp: (String) -> Void
    let onFilterApp: (FlowClientApp) -> Void
    let onFilterDevice: (String) -> Void
    
    var body: some View {
        if flows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 42))
                    .foregroundStyle(colors.textSecondary)
                Text(emptyMessage)
                    .font(DesignSystem.Fonts.mono(15, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                FlowTableHeader(colors: colors)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(flows) { flow in
                            let appID = FlowClientApp.normalizedID(flow.clientApp?.id ?? "")
                            FlowTableRow(
                                flow: flow,
                                isSelected: selection == flow.id,
                                colors: colors,
                                isHostPinned: pinnedHostnames.contains(PinnedHost.normalized(flow.host)),
                                isAppPinned: !appID.isEmpty && pinnedAppIDs.contains(appID),
                                onSelect: { selection = flow.id },
                                onMapLocal: {
                                    selection = flow.id
                                    onMapLocal(flow)
                                },
                                onEditRetry: {
                                    selection = flow.id
                                    onEditRetry(flow)
                                },
                                onPinHost: { onPinHost(flow.host) },
                                onUnpinHost: { onUnpinHost(flow.host) },
                                onPinApp: {
                                    guard let app = flow.clientApp else { return }
                                    onPinApp(app)
                                },
                                onUnpinApp: {
                                    guard let app = flow.clientApp else { return }
                                    onUnpinApp(app.id)
                                },
                                onFilterApp: {
                                    guard let app = flow.clientApp else { return }
                                    onFilterApp(app)
                                },
                                onFilterDevice: { onFilterDevice(flow.clientIP) }
                            )
                        }
                    }
                }
            }
            .background(colors.surface)
            .background(
                KeyEventMonitorView { event in
                    handleKeyEvent(event)
                }
            )
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !flows.isEmpty else { return false }
        guard shouldHandleKeyboardNavigation() else { return false }
        let currentIndex = selection.flatMap { id in
            flows.firstIndex(where: { $0.id == id })
        }

        switch event.keyCode {
        case 125: // down
            let nextIndex = min((currentIndex ?? -1) + 1, flows.count - 1)
            selection = flows[nextIndex].id
            return true
        case 126: // up
            let nextIndex = max((currentIndex ?? flows.count) - 1, 0)
            selection = flows[nextIndex].id
            return true
        case 115: // home
            selection = flows.first?.id
            return true
        case 119: // end
            selection = flows.last?.id
            return true
        case 116: // page up
            let jump = 10
            let nextIndex = max((currentIndex ?? 0) - jump, 0)
            selection = flows[nextIndex].id
            return true
        case 121: // page down
            let jump = 10
            let nextIndex = min((currentIndex ?? -1) + jump, flows.count - 1)
            selection = flows[nextIndex].id
            return true
        default:
            return false
        }
    }

    private func shouldHandleKeyboardNavigation() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return true }
        if responder is NSTextView || responder is NSTextField {
            return false
        }
        return true
    }
}

private struct KeyEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(onKeyDown: onKeyDown)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private enum ColumnWidths {
    static let method: CGFloat = 86
    static let status: CGFloat = 112
    static let app: CGFloat = 210
    static let host: CGFloat = 220
    static let map: CGFloat = 64
    static let time: CGFloat = 118
}

private struct FlowTableHeader: View {
    let colors: DesignSystem.ColorPalette
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularHeader
            compactHeader
            minimalHeader
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(colors.surfaceElevated)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border),
            alignment: .bottom
        )
    }

    private var regularHeader: some View {
        HStack(spacing: 0) {
            headerLabel("Method")
                .frame(width: ColumnWidths.method, alignment: .leading)
            headerLabel("Path")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            headerLabel("Status")
                .frame(width: ColumnWidths.status, alignment: .leading)
            headerLabel("App")
                .frame(width: ColumnWidths.app, alignment: .leading)
            headerLabel("Host")
                .frame(width: ColumnWidths.host, alignment: .leading)
            headerLabel("Map")
                .frame(width: ColumnWidths.map, alignment: .center)
            headerLabel("Time")
                .frame(width: ColumnWidths.time, alignment: .trailing)
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            headerLabel("Method")
                .frame(width: ColumnWidths.method, alignment: .leading)
            headerLabel("Path")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            headerLabel("Status")
                .frame(width: ColumnWidths.status, alignment: .leading)
            headerLabel("App")
                .frame(width: ColumnWidths.app, alignment: .leading)
            headerLabel("Host")
                .frame(width: ColumnWidths.host, alignment: .leading)
        }
    }

    private var minimalHeader: some View {
        HStack(spacing: 0) {
            headerLabel("Method")
                .frame(width: ColumnWidths.method, alignment: .leading)
            headerLabel("Path")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            headerLabel("Status")
                .frame(width: ColumnWidths.status, alignment: .leading)
            headerLabel("App")
                .frame(width: ColumnWidths.app, alignment: .leading)
        }
    }
    
    private func headerLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DesignSystem.Fonts.mono(11, weight: .semibold))
            .foregroundStyle(colors.textSecondary)
    }
}

private struct FlowTableRow: View {
    let flow: MitmFlow
    let isSelected: Bool
    let colors: DesignSystem.ColorPalette
    let isHostPinned: Bool
    let isAppPinned: Bool
    let onSelect: () -> Void
    let onMapLocal: () -> Void
    let onEditRetry: () -> Void
    let onPinHost: () -> Void
    let onUnpinHost: () -> Void
    let onPinApp: () -> Void
    let onUnpinApp: () -> Void
    let onFilterApp: () -> Void
    let onFilterDevice: () -> Void

    @State private var shareAnchorView: NSView?
    
    var body: some View {
        Button(action: onSelect) {
            regularRow
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(rowBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            ShareAnchorView { view in
                shareAnchorView = view
            }
            .frame(width: 1, height: 1)
        )
        .contextMenu {
            FlowContextMenuContent(
                flow: flow,
                isHostPinned: isHostPinned,
                isAppPinned: isAppPinned,
                shareAnchorView: shareAnchorView,
                onEditRetry: onEditRetry,
                onMapLocal: onMapLocal,
                onPinHost: onPinHost,
                onUnpinHost: onUnpinHost,
                onPinApp: onPinApp,
                onUnpinApp: onUnpinApp,
                onFilterApp: onFilterApp,
                onFilterDevice: onFilterDevice
            )
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border.opacity(0.7)),
            alignment: .bottom
        )
    }

    private var regularRow: some View {
        HStack(spacing: 0) {
            methodLabel
                .frame(width: ColumnWidths.method, alignment: .leading)
            pathLabel
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            StatusBadge(status: flow.response?.status, colors: colors)
                .frame(width: ColumnWidths.status, alignment: .leading)
            appLabel
                .frame(width: ColumnWidths.app, alignment: .leading)
            hostLabel
                .frame(width: ColumnWidths.host, alignment: .leading)
            mapIndicator
                .frame(width: ColumnWidths.map, alignment: .center)
            timeLabel
                .frame(width: ColumnWidths.time, alignment: .trailing)
        }
    }

    private var methodLabel: some View {
        let method = flow.request?.method.uppercased() ?? "—"
        return Text(method)
            .font(DesignSystem.Fonts.mono(13, weight: .medium))
            .foregroundStyle(methodColor(for: method))
    }
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return Color.green
        case "POST": return Color.blue
        case "PUT": return Color.orange
        case "PATCH": return Color.purple
        case "DELETE": return Color.red
        default: return colors.textPrimary
        }
    }
    
    private var mapIndicator: some View {
        Group {
            if flow.isMapped {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(colors.accent)
                    .padding(6)
                    .background(
                        Circle().fill(colors.accent.opacity(0.12))
                    )
            } else {
                Text("—")
                    .foregroundStyle(colors.textSecondary.opacity(0.6))
            }
        }
    }
    
    private var rowBackground: some View {
        Group {
            if isSelected {
                colors.accent.opacity(0.18)
            } else {
                (flow.response?.status ?? 0) >= 400
                    ? colors.danger.opacity(0.08)
                    : colors.surface
            }
        }
    }

    private var hostLabel: some View {
        HStack(spacing: 6) {
            Text(flow.host)
                .font(DesignSystem.Fonts.mono(13, weight: .medium))
                .foregroundStyle(isHostPinned ? colors.accent : colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if isHostPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(colors.accent)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .help(flow.host)
    }

    private var appLabel: some View {
        let ip = flow.clientIP
        let appName = flow.clientApp?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Group {
            if appName.isEmpty, ip.isEmpty {
                Text("—")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary.opacity(0.6))
            } else if appName.isEmpty {
                Text(ip)
                    .font(DesignSystem.Fonts.mono(12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                HStack(spacing: 8) {
                    appIcon
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(appName)
                                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if isAppPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(colors.accent)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        if !ip.isEmpty {
                            Text(ip)
                                .font(DesignSystem.Fonts.mono(10))
                                .foregroundStyle(colors.textSecondary.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
                .help(appHelpText)
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        AppBadgeIconView(
            title: flow.clientApp?.displayName ?? "",
            seed: flow.clientApp?.id,
            size: 18
        )
    }

    private var appHelpText: String {
        guard let app = flow.clientApp else { return "" }
        let pidText = app.pid.map { "pid: \($0)" } ?? ""
        return [
            app.displayName,
            app.bundleIdentifier ?? "",
            pidText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private var pathLabel: some View {
        Text(flow.path)
            .font(DesignSystem.Fonts.mono(12))
            .foregroundStyle(colors.textPrimary)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var timeLabel: some View {
        Text(flow.formattedTimestamp)
            .font(DesignSystem.Fonts.mono(11))
            .foregroundStyle(colors.textSecondary)
    }
}
