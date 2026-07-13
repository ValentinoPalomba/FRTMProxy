import AppKit
import SwiftUI

enum FlowColumn: String, CaseIterable, Identifiable {
    case method, path, status, app, host, map, start, end, duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .method: return "Method"
        case .path: return "Path"
        case .status: return "Status"
        case .app: return "App"
        case .host: return "Host"
        case .map: return "Map"
        case .start: return "Start"
        case .end: return "End"
        case .duration: return "Duration"
        }
    }

    var isToggleable: Bool { self != .method && self != .path }
    var isSortable: Bool { self != .map }

    var width: CGFloat? {
        switch self {
        case .path: return nil
        case .method: return DesignSystem.Metrics.scaled(86)
        case .status: return DesignSystem.Metrics.scaled(112)
        case .app: return DesignSystem.Metrics.scaled(210)
        case .host: return DesignSystem.Metrics.scaled(220)
        case .map: return DesignSystem.Metrics.scaled(64)
        case .start: return DesignSystem.Metrics.scaled(128)
        case .end: return DesignSystem.Metrics.scaled(128)
        case .duration: return DesignSystem.Metrics.scaled(100)
        }
    }

    var alignment: Alignment {
        switch self {
        case .map: return .center
        case .start, .end, .duration: return .trailing
        default: return .leading
        }
    }
}

private extension View {
    @ViewBuilder
    func flowColumnFrame(_ column: FlowColumn) -> some View {
        if let width = column.width {
            frame(width: width, alignment: column.alignment)
        } else {
            frame(minWidth: 180, maxWidth: .infinity, alignment: column.alignment)
        }
    }
}

struct FlowTableView: View {
    let flows: [MitmFlow]
    @Binding var selection: String?
    @Binding var compareSelection: String?
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

    @State private var sortColumn: FlowColumn?
    @State private var sortAscending = true
    @AppStorage("inspector.hiddenFlowColumns") private var hiddenColumnsRaw = ""

    private var hiddenColumns: Set<String> {
        Set(hiddenColumnsRaw.split(separator: ",").map(String.init))
    }

    private var visibleColumns: [FlowColumn] {
        FlowColumn.allCases.filter { !hiddenColumns.contains($0.id) }
    }

    private var sortedFlows: [MitmFlow] {
        guard let sortColumn else { return flows }
        let sorted = flows.sorted { compare($0, $1, by: sortColumn) }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        if flows.isEmpty {
            StateView(
                kind: .empty(title: emptyMessage, message: nil, systemImage: "antenna.radiowaves.left.and.right"),
                palette: colors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                FlowTableHeader(
                    colors: colors,
                    visibleColumns: visibleColumns,
                    sortColumn: sortColumn,
                    sortAscending: sortAscending,
                    hiddenColumns: hiddenColumns,
                    onToggleSort: toggleSort,
                    onToggleColumn: toggleColumn
                )
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedFlows) { flow in
                            row(for: flow)
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

    private func row(for flow: MitmFlow) -> some View {
        let appID = FlowClientApp.normalizedID(flow.clientApp?.id ?? "")
        return FlowTableRow(
            flow: flow,
            visibleColumns: visibleColumns,
            isSelected: selection == flow.id,
            isCompareSelected: compareSelection == flow.id,
            colors: colors,
            isHostPinned: pinnedHostnames.contains(PinnedHost.normalized(flow.host)),
            isAppPinned: !appID.isEmpty && pinnedAppIDs.contains(appID),
            onSelect: {
                selection = flow.id
                compareSelection = nil
            },
            onCompareSelect: {
                compareSelection = (compareSelection == flow.id) ? nil : flow.id
            },
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

    private func toggleSort(_ column: FlowColumn) {
        guard column.isSortable else { return }
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    private func toggleColumn(_ column: FlowColumn) {
        guard column.isToggleable else { return }
        var hidden = hiddenColumns
        if hidden.contains(column.id) {
            hidden.remove(column.id)
        } else {
            hidden.insert(column.id)
        }
        hiddenColumnsRaw = hidden.sorted().joined(separator: ",")
    }

    private func compare(_ a: MitmFlow, _ b: MitmFlow, by column: FlowColumn) -> Bool {
        switch column {
        case .method:
            return (a.request?.method ?? "") < (b.request?.method ?? "")
        case .path:
            return a.path.localizedCaseInsensitiveCompare(b.path) == .orderedAscending
        case .status:
            return (a.response?.status ?? -1) < (b.response?.status ?? -1)
        case .app:
            return appSortKey(a).localizedCaseInsensitiveCompare(appSortKey(b)) == .orderedAscending
        case .host:
            return a.host.localizedCaseInsensitiveCompare(b.host) == .orderedAscending
        case .start:
            return startSortKey(a) < startSortKey(b)
        case .end:
            return (a.responseTimestamp ?? 0) < (b.responseTimestamp ?? 0)
        case .duration:
            return (a.duration ?? -1) < (b.duration ?? -1)
        case .map:
            return false
        }
    }

    private func appSortKey(_ flow: MitmFlow) -> String {
        let name = flow.clientApp?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? flow.clientIP : name
    }

    private func startSortKey(_ flow: MitmFlow) -> TimeInterval {
        flow.requestTimestamp ?? flow.timestamp ?? 0
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let list = sortedFlows
        guard !list.isEmpty else { return false }
        guard shouldHandleKeyboardNavigation() else { return false }
        let currentIndex = selection.flatMap { id in
            list.firstIndex(where: { $0.id == id })
        }

        switch event.keyCode {
        case 125:
            let nextIndex = min((currentIndex ?? -1) + 1, list.count - 1)
            selection = list[nextIndex].id
            return true
        case 126:
            let nextIndex = max((currentIndex ?? list.count) - 1, 0)
            selection = list[nextIndex].id
            return true
        case 115:
            selection = list.first?.id
            return true
        case 119:
            selection = list.last?.id
            return true
        case 116:
            let nextIndex = max((currentIndex ?? 0) - 10, 0)
            selection = list[nextIndex].id
            return true
        case 121:
            let nextIndex = min((currentIndex ?? -1) + 10, list.count - 1)
            selection = list[nextIndex].id
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

private struct FlowTableHeader: View {
    let colors: DesignSystem.ColorPalette
    let visibleColumns: [FlowColumn]
    let sortColumn: FlowColumn?
    let sortAscending: Bool
    let hiddenColumns: Set<String>
    let onToggleSort: (FlowColumn) -> Void
    let onToggleColumn: (FlowColumn) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns) { column in
                headerCell(column)
                    .flowColumnFrame(column)
            }
            columnMenu
                .frame(width: DesignSystem.Metrics.scaled(30), alignment: .center)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(colors.surfaceElevated)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border),
            alignment: .bottom
        )
    }

    private func headerCell(_ column: FlowColumn) -> some View {
        Button {
            onToggleSort(column)
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(column.title.uppercased())
                    .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                    .foregroundStyle(sortColumn == column ? colors.accent : colors.textSecondary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: DesignSystem.Metrics.font(9), weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: column.alignment)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!column.isSortable)
    }

    private var columnMenu: some View {
        Menu {
            ForEach(FlowColumn.allCases.filter(\.isToggleable)) { column in
                Toggle(column.title, isOn: Binding(
                    get: { !hiddenColumns.contains(column.id) },
                    set: { _ in onToggleColumn(column) }
                ))
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: DesignSystem.Metrics.font(11), weight: .semibold))
                .foregroundStyle(colors.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show or hide columns")
    }
}

private struct FlowTableRow: View {
    let flow: MitmFlow
    let visibleColumns: [FlowColumn]
    let isSelected: Bool
    let isCompareSelected: Bool
    let colors: DesignSystem.ColorPalette
    let isHostPinned: Bool
    let isAppPinned: Bool
    let onSelect: () -> Void
    let onCompareSelect: () -> Void
    let onMapLocal: () -> Void
    let onEditRetry: () -> Void
    let onPinHost: () -> Void
    let onUnpinHost: () -> Void
    let onPinApp: () -> Void
    let onUnpinApp: () -> Void
    let onFilterApp: () -> Void
    let onFilterDevice: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                onCompareSelect()
            } else {
                onSelect()
            }
        } label: {
            HStack(spacing: 0) {
                ForEach(visibleColumns) { column in
                    cell(for: column)
                        .flowColumnFrame(column)
                }
                Color.clear.frame(width: DesignSystem.Metrics.scaled(30))
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(rowBackgroundColor)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .help("⌘-click to set as compare target")
        .contextMenu {
            FlowContextMenuContent(
                flow: flow,
                isHostPinned: isHostPinned,
                isAppPinned: isAppPinned,
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func cell(for column: FlowColumn) -> some View {
        switch column {
        case .method: methodLabel
        case .path: pathLabel
        case .status: StatusBadge(status: flow.response?.status, colors: colors)
        case .app: appLabel
        case .host: hostLabel
        case .map: mapIndicator
        case .start: startLabel
        case .end: endLabel
        case .duration: durationLabel
        }
    }

    private var accessibilityText: String {
        let method = flow.request?.method.uppercased() ?? ""
        let status = flow.response?.status.map { "status \($0)" } ?? "pending"
        return "\(method) \(flow.host)\(flow.path), \(status)"
    }

    private var methodLabel: some View {
        let method = flow.request?.method.uppercased() ?? "—"
        return Text(method)
            .font(DesignSystem.Fonts.mono(13, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.methodColor(method, palette: colors))
    }

    private var mapIndicator: some View {
        Group {
            if flow.isMapped {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(colors.accent)
                    .padding(DesignSystem.Spacing.xs)
                    .background(Circle().fill(colors.accent.opacity(0.12)))
            } else {
                Text("—")
                    .foregroundStyle(colors.textSecondary.opacity(0.6))
            }
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return colors.accent.opacity(0.18)
        }
        if isCompareSelected {
            return colors.accentSecondary.opacity(0.18)
        }
        if (flow.response?.status ?? 0) >= 400 {
            return colors.danger.opacity(isHovering ? 0.13 : 0.08)
        }
        if isHovering {
            return colors.textPrimary.opacity(0.05)
        }
        return colors.surface
    }

    private var hostLabel: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Text(flow.host)
                .font(DesignSystem.Fonts.mono(13, weight: .medium))
                .foregroundStyle(isHostPinned ? colors.accent : colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if isHostPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(colors.accent)
                    .font(.system(size: DesignSystem.Metrics.font(11), weight: .semibold))
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
                HStack(spacing: DesignSystem.Spacing.sm) {
                    AppBadgeIconView(
                        title: flow.clientApp?.displayName ?? "",
                        seed: flow.clientApp?.id,
                        size: DesignSystem.Metrics.scaled(18)
                    )
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text(appName)
                                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if isAppPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(colors.accent)
                                    .font(.system(size: DesignSystem.Metrics.font(11), weight: .semibold))
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

    private var appHelpText: String {
        guard let app = flow.clientApp else { return "" }
        let pidText = app.pid.map { "pid: \($0)" } ?? ""
        return [app.displayName, app.bundleIdentifier ?? "", pidText]
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

    private var startLabel: some View {
        Text(flow.formattedStartTimestamp)
            .font(DesignSystem.Fonts.mono(11))
            .foregroundStyle(colors.textSecondary)
    }

    private var endLabel: some View {
        Text(flow.formattedEndTimestamp)
            .font(DesignSystem.Fonts.mono(11))
            .foregroundStyle(colors.textSecondary)
    }

    private var durationLabel: some View {
        Text(flow.formattedDuration)
            .font(DesignSystem.Fonts.mono(11))
            .foregroundStyle(colors.textSecondary)
    }
}
