import SwiftUI

struct InspectorHeaderBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
    @Binding var filter: FlowFilter
    let pinnedApps: [PinnedApp]
    let pinnedHosts: [PinnedHost]
    let clientIPs: [String]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void
    let onShowRules: () -> Void
    let onShowBreakpoints: () -> Void
    let onShowCollections: () -> Void
    let onShowDeviceConnect: () -> Void
    let trafficProfiles: [TrafficProfile]
    let activeTrafficProfile: TrafficProfile
    let onSelectTrafficProfile: (TrafficProfile) -> Void
    let onToggleProxy: () -> Void

    private var toggleTitle: String {
        isRunning ? "Stop" : "Start"
    }

    private var toggleSystemImage: String {
        isRunning ? "stop.fill" : "play.fill"
    }

    private var toggleStyle: ControlButtonStyle {
        isRunning ? .destructive(colors) : .filled(colors)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Metrics.scaled(14)) {
            FlowFiltersView(
                filter: $filter,
                colors: colors,
                pinnedApps: pinnedApps,
                pinnedHosts: pinnedHosts,
                clientIPs: clientIPs,
                onTogglePinnedHost: onTogglePinnedHost,
                onRemovePinnedHost: onRemovePinnedHost,
                onTogglePinnedApp: onTogglePinnedApp,
                onRemovePinnedApp: onRemovePinnedApp
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                ManageMenuButton(
                    colors: colors,
                    trafficProfiles: trafficProfiles,
                    activeTrafficProfile: activeTrafficProfile,
                    onSelectTrafficProfile: onSelectTrafficProfile,
                    onShowRules: onShowRules,
                    onShowBreakpoints: onShowBreakpoints,
                    onShowCollections: onShowCollections,
                    onShowDeviceConnect: onShowDeviceConnect
                )
                ControlButton(
                    title: toggleTitle,
                    systemImage: toggleSystemImage,
                    style: toggleStyle,
                    disabled: false
                ) {
                    onToggleProxy()
                }
                .onboardingTarget(.startProxy)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(10))
    }
}

private struct ManageMenuButton: View {
    let colors: DesignSystem.ColorPalette
    let trafficProfiles: [TrafficProfile]
    let activeTrafficProfile: TrafficProfile
    let onSelectTrafficProfile: (TrafficProfile) -> Void
    let onShowRules: () -> Void
    let onShowBreakpoints: () -> Void
    let onShowCollections: () -> Void
    let onShowDeviceConnect: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Manage", systemImage: "ellipsis")
                .font(DesignSystem.Fonts.mono(13, weight: .semibold))
                .padding(.horizontal, DesignSystem.Metrics.scaled(14))
                .padding(.vertical, DesignSystem.Metrics.scaled(9))
                .frame(minHeight: DesignSystem.Metrics.scaled(34))
                .background(colors.surface)
                .foregroundStyle(colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10)))
        }
        .buttonStyle(.plain)
        .onboardingTarget(.manageMenu)
        .onboardingTarget(.configureWiFiProxy)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(14)) {
                Text("Quick actions")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                menuButton(title: "Rules", icon: "slider.horizontal.3", action: {
                    isPresented = false
                    onShowRules()
                })
                menuButton(title: "Breakpoints", icon: "record.circle", action: {
                    isPresented = false
                    onShowBreakpoints()
                })
                menuButton(title: "Collections", icon: "folder", action: {
                    isPresented = false
                    onShowCollections()
                })
                menuButton(title: "Device", icon: "qrcode", action: {
                    isPresented = false
                    onShowDeviceConnect()
                })

                Divider()
                    .padding(.vertical, DesignSystem.Metrics.scaled(4))

                TrafficProfileSection(
                    colors: colors,
                    profiles: trafficProfiles,
                    activeProfile: activeTrafficProfile,
                    onSelect: { profile in
                        isPresented = false
                        onSelectTrafficProfile(profile)
                    }
                )
            }
            .padding(DesignSystem.Metrics.scaled(16))
            .frame(width: DesignSystem.Metrics.scaled(280))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(16))
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
            )
        }
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Metrics.scaled(10)) {
                Image(systemName: icon)
                Text(title)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(colors.textPrimary)
            .padding(.vertical, DesignSystem.Metrics.scaled(6))
        }
        .buttonStyle(.plain)
    }
}

private struct TrafficProfileSection: View {
    let colors: DesignSystem.ColorPalette
    let profiles: [TrafficProfile]
    let activeProfile: TrafficProfile
    let onSelect: (TrafficProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(12)) {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(2)) {
                Text("Traffic profiles")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text("Simulate degraded networks directly on the proxy.")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary.opacity(0.8))
            }

            VStack(spacing: DesignSystem.Metrics.scaled(8)) {
                ForEach(profiles) { profile in
                    profileButton(profile)
                }
            }
        }
    }

    @ViewBuilder
    private func profileButton(_ profile: TrafficProfile) -> some View {
        let isActive = profile.id == activeProfile.id
        Button {
            onSelect(profile)
        } label: {
            HStack(alignment: .center, spacing: DesignSystem.Metrics.scaled(12)) {
                Image(systemName: profile.systemImageName)
                    .foregroundStyle(isActive ? colors.accent : colors.textSecondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(profile.summary)
                        .font(DesignSystem.Fonts.sans(11, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                }
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(12))
            .padding(.vertical, DesignSystem.Metrics.scaled(10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
                    .fill(isActive ? colors.accent.opacity(0.12) : colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
                    .stroke(isActive ? colors.accent.opacity(0.6) : colors.border.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
