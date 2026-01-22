import SwiftUI

struct FlowTableView: View {
    let flows: [MitmFlow]
    @Binding var selection: String?
    let emptyMessage: String
    let colors: DesignSystem.ColorPalette
    let pinnedHostnames: Set<String>
    let onMapLocal: (MitmFlow) -> Void
    let onEditRetry: (MitmFlow) -> Void
    let onPinHost: (String) -> Void
    let onUnpinHost: (String) -> Void
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
                            FlowTableRow(
                                flow: flow,
                                isSelected: selection == flow.id,
                                colors: colors,
                                isHostPinned: pinnedHostnames.contains(PinnedHost.normalized(flow.host)),
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
                                onFilterDevice: { onFilterDevice(flow.clientIP) }
                            )
                        }
                    }
                }
            }
            .background(colors.surface)
        }
    }
}

private struct FlowTableHeader: View {
    let colors: DesignSystem.ColorPalette
    
    var body: some View {
        HStack(spacing: 0) {
            headerLabel("Method")
                .frame(width: 90, alignment: .leading)
            headerLabel("Path")
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            headerLabel("Status")
                .frame(width: 120, alignment: .leading)
            headerLabel("Device")
                .frame(width: 150, alignment: .leading)
            headerLabel("Host")
                .frame(width: 200, alignment: .leading)
            headerLabel("Map")
                .frame(width: 70, alignment: .center)
            headerLabel("Time")
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.surfaceElevated)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border),
            alignment: .bottom
        )
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
    let onSelect: () -> Void
    let onMapLocal: () -> Void
    let onEditRetry: () -> Void
    let onPinHost: () -> Void
    let onUnpinHost: () -> Void
    let onFilterDevice: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                methodLabel
                    .frame(width: 90, alignment: .leading)
                Text(flow.path)
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                StatusBadge(status: flow.response?.status, colors: colors)
                    .frame(width: 120, alignment: .leading)
                deviceLabel
                    .frame(width: 150, alignment: .leading)
                hostLabel
                    .frame(width: 200, alignment: .leading)
                mapIndicator
                    .frame(width: 70, alignment: .center)
                Text(flow.formattedTimestamp)
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 130, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(rowBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEditRetry()
            } label: {
                Label("Edit & Retry", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                onMapLocal()
            } label: {
                Label("Map Local", systemImage: "pencil.and.outline")
            }
            if !flow.clientIP.isEmpty {
                Button {
                    onFilterDevice()
                } label: {
                    Label("Filter device", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            if !flow.host.isEmpty {
                if isHostPinned {
                    Button {
                        onUnpinHost()
                    } label: {
                        Label("Unpin host", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        onPinHost()
                    } label: {
                        Label("Pin host", systemImage: "pin")
                    }
                }
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(colors.border.opacity(0.7)),
            alignment: .bottom
        )
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
            if isHostPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(colors.accent)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }

    private var deviceLabel: some View {
        let ip = flow.clientIP
        return Group {
            if ip.isEmpty {
                Text("—")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary.opacity(0.6))
            } else {
                Text(ip)
                    .font(DesignSystem.Fonts.mono(12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }
}
