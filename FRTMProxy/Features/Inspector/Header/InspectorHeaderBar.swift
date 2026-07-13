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
    let onShowComposer: () -> Void
    let onShowScripts: () -> Void
    let trafficProfiles: [TrafficProfile]
    let activeTrafficProfile: TrafficProfile
    let onSelectTrafficProfile: (TrafficProfile) -> Void
    let onToggleProxy: () -> Void

    private var toggleTitle: LocalizedStringKey {
        isRunning ? "Stop" : "Start"
    }

    private var toggleSystemImage: String {
        isRunning ? "stop.fill" : "play.fill"
    }

    private var toggleStyle: ControlButtonStyle {
        isRunning ? .destructive(colors) : .filled(colors)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
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

            HStack(spacing: DesignSystem.Spacing.sm) {
                ManageMenuButton(
                    colors: colors,
                    trafficProfiles: trafficProfiles,
                    activeTrafficProfile: activeTrafficProfile,
                    onSelectTrafficProfile: onSelectTrafficProfile,
                    onShowRules: onShowRules,
                    onShowBreakpoints: onShowBreakpoints,
                    onShowCollections: onShowCollections,
                    onShowDeviceConnect: onShowDeviceConnect,
                    onShowComposer: onShowComposer,
                    onShowScripts: onShowScripts
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
        .padding(.horizontal, DesignSystem.Spacing.sm)
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
    let onShowComposer: () -> Void
    let onShowScripts: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Manage", systemImage: "ellipsis")
                .font(DesignSystem.Fonts.mono(13, weight: .semibold))
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .frame(minHeight: DesignSystem.Metrics.scaled(34))
                .background(colors.surface)
                .foregroundStyle(colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                sectionHeader("Settings")
                menuButton(title: "Rules", icon: "slider.horizontal.3", action: {
                    isPresented = false; onShowRules()
                })
                menuButton(title: "Breakpoints", icon: "record.circle", action: {
                    isPresented = false; onShowBreakpoints()
                })
                menuButton(title: "Collections", icon: "folder", action: {
                    isPresented = false; onShowCollections()
                })
                menuButton(title: "Device", icon: "qrcode", action: {
                    isPresented = false; onShowDeviceConnect()
                })

                sectionHeader("Tools")
                    .padding(.top, DesignSystem.Spacing.sm)
                menuButton(title: "Compose", icon: "paperplane.fill", action: {
                    isPresented = false; onShowComposer()
                })
                menuButton(title: "Scripts", icon: "curlybraces", action: {
                    isPresented = false; onShowScripts()
                })

                Divider()
                    .padding(.vertical, DesignSystem.Spacing.xs)

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
            .padding(DesignSystem.Spacing.lg)
            .frame(width: DesignSystem.Metrics.scaled(280))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
            )
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DesignSystem.Fonts.sans(10, weight: .semibold))
            .foregroundStyle(colors.textSecondary.opacity(0.7))
            .tracking(0.8)
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                Text(title)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(colors.textPrimary)
            .padding(.vertical, DesignSystem.Spacing.sm)
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text("Traffic profiles")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text("Simulate degraded networks directly on the proxy.")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary.opacity(0.8))
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
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
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                Image(systemName: profile.systemImageName)
                    .foregroundStyle(isActive ? colors.accent : colors.textSecondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(profile.name)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(profileSubtitle(for: profile))
                        .font(DesignSystem.Fonts.sans(11, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                    .fill(isActive ? colors.accent.opacity(0.12) : colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                    .stroke(isActive ? colors.accent.opacity(0.6) : colors.border.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func profileSubtitle(for profile: TrafficProfile) -> String {
        if profile.id == TrafficProfileLibrary.manualID {
            return profile.summary + " · Customize in Settings > Traffic"
        }
        return profile.summary
    }
}
