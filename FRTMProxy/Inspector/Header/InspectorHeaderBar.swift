import SwiftUI

struct InspectorHeaderBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
    let lastFlow: MitmFlow?
    let onClear: () -> Void
    let onShowRules: () -> Void
    let onShowBreakpoints: () -> Void
    let onShowCollections: () -> Void
    let onShowDeviceConnect: () -> Void
    let trafficProfiles: [TrafficProfile]
    let activeTrafficProfile: TrafficProfile
    let onSelectTrafficProfile: (TrafficProfile) -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    private var octoState: OctoState {
        guard let lastFlow else { return .idle }
        if let status = lastFlow.response?.status {
            return status >= 400 ? .error : .running
        }
        return .running
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                OctoPixelBadge(colors: colors, state: octoState, embedded: true)
                StatusPill(isRunning: isRunning, colors: colors)
            }
            .padding(.bottom, -8)
            .padding(.top, -4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.border.opacity(0.7), lineWidth: 1)
                    )
            )

            Spacer()

            HStack(spacing: 8) {
                ControlButton(title: "Clear", systemImage: "trash", style: .ghost(colors), disabled: false) {
                    onClear()
                }
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
                ControlButton(title: "Start", systemImage: "play.fill", style: .filled(colors), disabled: isRunning) {
                    onStart()
                }
                .onboardingTarget(.startProxy)
                ControlButton(title: "Stop", systemImage: "stop.fill", style: .destructive(colors), disabled: !isRunning) {
                    onStop()
                }
            }
        }
        .padding(.horizontal, 4)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 34)
                .background(colors.surface)
                .foregroundStyle(colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
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
                    .padding(.vertical, 4)

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
            .padding(16)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
            )
        }
    }

    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(colors.textPrimary)
            .padding(.vertical, 6)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Traffic profiles")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text("Simulate degraded networks directly on the proxy.")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary.opacity(0.8))
            }

            VStack(spacing: 8) {
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
            HStack(alignment: .center, spacing: 12) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? colors.accent.opacity(0.12) : colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? colors.accent.opacity(0.6) : colors.border.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
