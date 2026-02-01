import SwiftUI

struct FlowFiltersView: View {
    @Binding var filter: FlowFilter
    let colors: DesignSystem.ColorPalette
    let pinnedApps: [PinnedApp]
    let pinnedHosts: [PinnedHost]
    let clientIPs: [String]
    let onReset: () -> Void
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SearchField(text: $filter.searchText, placeholder: "Search: keywords, host:, app:, method:, status:, type:, device: (use -term to exclude)", colors: colors)
                ControlButton(title: "Reset", systemImage: "arrow.uturn.left", style: .ghost(colors), disabled: !hasCustomFilters) {
                    onReset()
                }
            }

            if !pinnedApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pinned apps")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(pinnedApps) { app in
                                PinnedAppChip(
                                    app: app,
                                    colors: colors,
                                    onToggle: { onTogglePinnedApp(app) },
                                    onRemove: { onRemovePinnedApp(app) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                Text("Pin any app from the table to keep it here for quick filtering.")
                    .font(DesignSystem.Fonts.sans(11))
                    .foregroundStyle(colors.textSecondary.opacity(0.8))
            }

            if !pinnedHosts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pinned hosts")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(pinnedHosts) { host in
                                PinnedHostChip(
                                    host: host,
                                    colors: colors,
                                    onToggle: { onTogglePinnedHost(host) },
                                    onRemove: { onRemovePinnedHost(host) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                Text("Pin any host from the table to keep it here for quick filtering.")
                    .font(DesignSystem.Fonts.sans(11))
                    .foregroundStyle(colors.textSecondary.opacity(0.8))
            }

            if clientIPs.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Devices")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(clientIPs, id: \.self) { ip in
                                DeviceChip(
                                    ip: ip,
                                    isActive: filter.activeClientIPs.contains(ip),
                                    colors: colors
                                ) {
                                    filter.toggleClientIP(ip)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            HStack(spacing: 8) {
                FilterChip(
                    title: "Mapped",
                    isOn: $filter.showMappedOnly,
                    color: colors.accent,
                    colors: colors
                )
                FilterChip(
                    title: "Errori",
                    isOn: $filter.showErrorsOnly,
                    color: colors.warning,
                    colors: colors
                )
                Spacer()
            }
        }
    }

    private var hasCustomFilters: Bool {
        !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        filter.showMappedOnly ||
        filter.showErrorsOnly ||
        !filter.activePinnedHosts.isEmpty ||
        !filter.activePinnedApps.isEmpty ||
        !filter.activeClientIPs.isEmpty
    }
}

private struct DeviceChip: View {
    let ip: String
    let isActive: Bool
    let colors: DesignSystem.ColorPalette
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 12, weight: .semibold))
                Text(ip)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(isActive ? colors.accent.opacity(0.18) : colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(isActive ? colors.accent : colors.border, lineWidth: 1)
            )
            .foregroundStyle(isActive ? colors.accent : colors.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

private struct PinnedHostChip: View {
    let host: PinnedHost
    let colors: DesignSystem.ColorPalette
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: host.isActive ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                Text(host.host)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(host.isActive ? colors.accent.opacity(0.18) : colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(host.isActive ? colors.accent : colors.border, lineWidth: 1)
            )
            .foregroundStyle(host.isActive ? colors.accent : colors.textPrimary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove pin", systemImage: "trash")
            }
        }
    }
}

private struct PinnedAppChip: View {
    let app: PinnedApp
    let colors: DesignSystem.ColorPalette
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                appIcon
                Image(systemName: app.isActive ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                Text(app.displayName.isEmpty ? app.appID : app.displayName)
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(app.isActive ? colors.accent.opacity(0.18) : colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(app.isActive ? colors.accent : colors.border, lineWidth: 1)
            )
            .foregroundStyle(app.isActive ? colors.accent : colors.textPrimary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove pin", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        AppBadgeIconView(
            title: app.displayName.isEmpty ? app.appID : app.displayName,
            seed: app.appID,
            size: 14
        )
    }
}
