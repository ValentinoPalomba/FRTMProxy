import SwiftUI

struct FlowFiltersView: View {
    @Binding var filter: FlowFilter
    let colors: DesignSystem.ColorPalette
    let pinnedApps: [PinnedApp]
    let pinnedHosts: [PinnedHost]
    let clientIPs: [String]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
            HStack(spacing: DesignSystem.Metrics.scaled(10)) {
                SearchField(
                    text: $filter.searchText,
                    placeholder: "Search: keywords, host:, app:, method:, status:, type:, device: (use -term to exclude)",
                    colors: colors
                )
                .frame(minWidth: DesignSystem.Metrics.scaled(160), maxWidth: .infinity)
                .layoutPriority(0)
            }

            if !pinnedApps.isEmpty || !pinnedHosts.isEmpty || clientIPs.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                        ForEach(pinnedApps) { app in
                            PinnedAppChip(
                                app: app,
                                colors: colors,
                                onToggle: { onTogglePinnedApp(app) },
                                onRemove: { onRemovePinnedApp(app) }
                            )
                        }
                        ForEach(pinnedHosts) { host in
                            PinnedHostChip(
                                host: host,
                                colors: colors,
                                onToggle: { onTogglePinnedHost(host) },
                                onRemove: { onRemovePinnedHost(host) }
                            )
                        }
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
                    .padding(.vertical, DesignSystem.Metrics.scaled(2))
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct DeviceChip: View {
    let ip: String
    let isActive: Bool
    let colors: DesignSystem.ColorPalette
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                Image(systemName: "iphone")
                    .font(.system(size: DesignSystem.Metrics.scaled(12), weight: .semibold))
                Text(ip)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(12))
            .padding(.vertical, DesignSystem.Metrics.scaled(6))
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
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                Image(systemName: host.isActive ? "pin.fill" : "pin")
                    .font(.system(size: DesignSystem.Metrics.scaled(12), weight: .semibold))
                Text(host.host)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(12))
            .padding(.vertical, DesignSystem.Metrics.scaled(6))
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
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                appIcon
                Image(systemName: app.isActive ? "pin.fill" : "pin")
                    .font(.system(size: DesignSystem.Metrics.scaled(12), weight: .semibold))
                Text(app.displayName.isEmpty ? app.appID : app.displayName)
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(12))
            .padding(.vertical, DesignSystem.Metrics.scaled(6))
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
            size: DesignSystem.Metrics.scaled(14)
        )
    }
}
