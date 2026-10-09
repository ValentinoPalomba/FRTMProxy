import SwiftUI

struct InspectorHeaderBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
    @Binding var filter: FlowFilter
    @ObservedObject var profileStore: CaptureProfileStore
    let onCreateProfile: () -> Void
    let pinnedApps: [PinnedApp]
    let pinnedHosts: [PinnedHost]
    let clientIPs: [String]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void
    let onShowRules: () -> Void
    let onShowUnifiedRules: () -> Void
    let onShowBreakpoints: () -> Void
    let onShowCollections: () -> Void
    let onShowDeviceConnect: () -> Void
    let onShowComposer: () -> Void
    let onShowScripts: () -> Void
    let onShowSessions: () -> Void
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
                pinnedApps: profileStore.activeProfileID == nil ? pinnedApps : [],
                pinnedHosts: profileStore.activeProfileID == nil ? pinnedHosts : [],
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
                    profileStore: profileStore,
                    onCreateProfile: onCreateProfile,
                    trafficProfiles: trafficProfiles,
                    activeTrafficProfile: activeTrafficProfile,
                    onSelectTrafficProfile: onSelectTrafficProfile,
                    onShowRules: onShowRules,
                    onShowUnifiedRules: onShowUnifiedRules,
                    onShowBreakpoints: onShowBreakpoints,
                    onShowCollections: onShowCollections,
                    onShowDeviceConnect: onShowDeviceConnect,
                    onShowComposer: onShowComposer,
                    onShowScripts: onShowScripts,
                    onShowSessions: onShowSessions
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
    @ObservedObject var profileStore: CaptureProfileStore
    let onCreateProfile: () -> Void
    let trafficProfiles: [TrafficProfile]
    let activeTrafficProfile: TrafficProfile
    let onSelectTrafficProfile: (TrafficProfile) -> Void
    let onShowRules: () -> Void
    let onShowUnifiedRules: () -> Void
    let onShowBreakpoints: () -> Void
    let onShowCollections: () -> Void
    let onShowDeviceConnect: () -> Void
    let onShowComposer: () -> Void
    let onShowScripts: () -> Void
    let onShowSessions: () -> Void
    @State private var isPresented = false
    @State private var showsProfilesManager = false
    @State private var showsAdvancedTools = false

    var body: some View {
        ControlButton(
            title: "Manage",
            systemImage: "ellipsis",
            style: .ghost(colors)
        ) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                menuButton(title: "Map Local Rules", icon: "slider.horizontal.3", action: {
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

                Divider()
                    .padding(.vertical, DesignSystem.Spacing.xs)

                advancedToolsSection

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
            .frame(width: DesignSystem.Metrics.scaled(300))
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
            )
        }
        .sheet(isPresented: $showsProfilesManager) {
            CaptureProfilesManagerView(store: profileStore, colors: colors)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { showsAdvancedTools = false }
        }
    }

    private var advancedToolsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Button { showsAdvancedTools.toggle() } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .frame(width: DesignSystem.Metrics.scaled(18))
                        .foregroundStyle(colors.textSecondary)
                    Text("Advanced Tools")
                        .font(DesignSystem.Fonts.body.weight(.medium))
                    Spacer()
                    Image(systemName: showsAdvancedTools ? "chevron.down" : "chevron.right")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.pressable)
            .hoverHighlight(colors, cornerRadius: DesignSystem.Radius.sm)
            .accessibilityIdentifier("inspector.advancedTools")
            .accessibilityValue(showsAdvancedTools ? Text("Expanded") : Text("Collapsed"))

            if showsAdvancedTools {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Capture profiles")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                    CaptureProfilesControl(
                        store: profileStore, colors: colors,
                        onCreate: {
                            isPresented = false
                            onCreateProfile()
                        },
                        onManage: {
                            isPresented = false
                            showsProfilesManager = true
                        }
                    )
                    menuButton(title: "Sessions", icon: "clock.arrow.circlepath") {
                        isPresented = false; onShowSessions()
                    }
                    menuButton(title: "Traffic Rules", icon: "point.3.connected.trianglepath.dotted") {
                        isPresented = false; onShowUnifiedRules()
                    }
                    menuButton(title: "Scripts", icon: "curlybraces") {
                        isPresented = false; onShowScripts()
                    }
                    menuButton(title: "Compose", icon: "paperplane.fill") {
                        isPresented = false; onShowComposer()
                    }
                }
                .padding(.leading, DesignSystem.Spacing.md)
            }
        }
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .frame(width: DesignSystem.Metrics.scaled(18))
                    .foregroundStyle(colors.textSecondary)
                Text(LocalizedStringKey(title))
                    .font(DesignSystem.Fonts.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .hoverHighlight(colors, cornerRadius: DesignSystem.Radius.sm)
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
                    Text(LocalizedStringKey(profile.name))
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
            return profile.summary + " · " + String(localized: "Customize in Settings > Traffic", bundle: AppLocalization.bundle)
        }
        return profile.summary
    }
}
