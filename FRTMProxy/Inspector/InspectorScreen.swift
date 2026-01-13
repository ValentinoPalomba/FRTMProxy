import SwiftUI

struct InspectorScreen: View {
    @ObservedObject var viewModel: ProxyViewModel
    @ObservedObject var rulesViewModel: MapRuleViewModel
    @StateObject private var mapEditorViewModel = MapEditorViewModel()
    @StateObject private var retryEditorViewModel = MapEditorViewModel()
    @StateObject private var breakpointEditorViewModel = MapEditorViewModel()

    @State private var showMapSheet = false
    @State private var showRulesSheet = false
    @State private var showCollectionsSheet = false
    @State private var showRetrySheet = false
    @State private var showBreakpointSheet = false
    @State private var showBreakpointsManager = false
    @State private var showDeviceConnectSheet = false
    @State private var filter = FlowFilter()
    @State private var activeBreakpointPhase: FlowBreakpointPhase = .request
    @State private var filteredFlows: [MitmFlow] = []

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    @State private var inspectorHeight: CGFloat = 320
    @GestureState private var inspectorDrag: CGFloat = 0

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var selectedFlow: MitmFlow? {
        viewModel.selectedFlow
    }

    var body: some View {
        let availableClientIPs = Array(
            Set(viewModel.flows.map(\.clientIP).filter { !$0.isEmpty })
        ).sorted()
        let trafficProfiles = TrafficProfileLibrary.presets

        let content = VStack(spacing: 16) {
            InspectorHeaderBar(
                colors: colors,
                isRunning: viewModel.isRunning,
                onClear: viewModel.clear,
                onShowRules: { showRulesSheet = true },
                onShowBreakpoints: { showBreakpointsManager = true },
                onShowCollections: { showCollectionsSheet = true },
                onShowDeviceConnect: { showDeviceConnectSheet = true },
                trafficProfiles: trafficProfiles,
                activeTrafficProfile: viewModel.activeTrafficProfile,
                onSelectTrafficProfile: { profile in
                    viewModel.selectTrafficProfile(profile)
                    settings.selectedTrafficProfileID = profile.id
                },
                onStart: { viewModel.startProxy() },
                onStop: viewModel.stopProxy
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    FlowExplorerSection(
                        filter: $filter,
                        flows: filteredFlows,
                        clientIPs: availableClientIPs,
                        selection: $viewModel.selectedFlowID,
                        colors: colors,
                        emptyMessage: viewModel.flows.isEmpty ? "In attesa di traffico..." : "Nessun risultato per i filtri",
                        pinnedHosts: settings.pinnedHosts,
                        onTogglePinnedHost: { togglePinnedHost($0) },
                        onRemovePinnedHost: { removePinnedHost($0) },
                        onResetFilters: resetFilters,
                        onMapLocal: { flow in openMapEditor(flow: flow) },
                        onEditRetry: { flow in openRetryEditor(for: flow) },
                        onPinHost: { pinHost(host: $0) },
                        onUnpinHost: { removePinnedHost(byHostName: $0) },
                        onFilterDevice: { ip in
                            filter.activeClientIPs = [ip]
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal,20)

                    if let flow = selectedFlow {
                        let maxHeight = max(proxy.size.height * 0.9, inspectorMinHeight + 40)
                        let currentHeight = min(
                            maxHeight,
                            max(inspectorMinHeight, inspectorHeight + inspectorDrag)
                        )

                        FlowInspectorPanel(
                            flow: flow,
                            colors: colors,
                            displayHeight: currentHeight,
                            maxHeight: maxHeight,
                            onMapLocal: openMapEditor,
                            onCopyUrl: { ClipboardHelper.copy(flow.request?.url) },
                            onCopyCurl: { ClipboardHelper.copy(flow.curlString) },
                            onCopyBody: { ClipboardHelper.copy(flow.response?.body) },
                            isRequestBreakpointEnabled: viewModel.isBreakpointEnabled(for: flow, phase: .request),
                            isResponseBreakpointEnabled: viewModel.isBreakpointEnabled(for: flow, phase: .response),
                            onToggleBreakpoint: { phase, enabled in
                                viewModel.setBreakpoint(for: flow, phase: phase, enabled: enabled)
                            }
                        )
                        .gesture(inspectorDragGesture(maxHeight: maxHeight))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }

        let contentWithFiltering = content
        .background(colors.background)
        .task {
            updateFilteredFlows()
        }
        .onChange(of: viewModel.flows) { _, _ in
            updateFilteredFlows()
        }
        .onChange(of: filter) { _, _ in
            updateFilteredFlows()
        }

        return contentWithFiltering
        .sheet(isPresented: $showMapSheet) { mapSheet }
        .sheet(isPresented: $showRulesSheet) { rulesSheet }
        .sheet(isPresented: $showCollectionsSheet) { collectionsSheet }
        .sheet(isPresented: $showRetrySheet) { retrySheet }
        .sheet(isPresented: $showBreakpointSheet) { breakpointSheet }
        .sheet(isPresented: $showBreakpointsManager) {
            BreakpointsManagerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showDeviceConnectSheet) {
            DeviceConnectView(proxyPort: viewModel.activePort, proxyIsRunning: viewModel.isRunning)
                .environmentObject(settings)
        }
        .onChange(of: viewModel.rules) { _, _ in
            rulesViewModel.load(sortedRules())
        }
        .onChange(of: showRulesSheet) { _, shown in
            if shown {
                rulesViewModel.load(sortedRules())
            }
        }
        .onChange(of: viewModel.selectedFlowID) { _, newValue in
            if newValue == nil {
                inspectorHeight = inspectorMinHeight
            }
        }
        .onChange(of: showBreakpointSheet) { _, shown in
            if !shown, viewModel.activeBreakpointHit != nil {
                viewModel.skipActiveBreakpoint()
            }
        }
        .onChange(of: viewModel.activeBreakpointHit) { _, hit in
            guard let hit,
                  let flow = viewModel.flow(withID: hit.flowID) else {
                showBreakpointSheet = false
                return
            }
            openBreakpointEditor(for: flow, phase: hit.phase)
        }
        .onAppear {
            syncPinnedHostFilterState()
        }
        .onChange(of: settings.pinnedHosts) { _, _ in
            syncPinnedHostFilterState()
        }
    }

    private func updateFilteredFlows() {
        filteredFlows = filter.apply(to: viewModel.flows)
    }

    private func openMapEditor() {
        guard let flow = selectedFlow else { return }
        openMapEditor(flow: flow)
    }

    private func openMapEditor(flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        mapEditorViewModel.load(flow: flow)
        showMapSheet = true
    }

    private func openRetryEditor(for flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        retryEditorViewModel.load(flow: flow)
        showRetrySheet = true
    }
    
    private func openBreakpointEditor(for flow: MitmFlow, phase: FlowBreakpointPhase) {
        viewModel.selectedFlowID = flow.id
        breakpointEditorViewModel.load(flow: flow)
        activeBreakpointPhase = phase
        showBreakpointSheet = true
    }

    private func pinHost(host: String) {
        settings.pinHost(host)
        syncPinnedHostFilterState()
    }

    private func removePinnedHost(_ host: PinnedHost) {
        settings.unpinHost(host.host)
        syncPinnedHostFilterState()
    }

    private func removePinnedHost(byHostName host: String) {
        settings.unpinHost(host)
        syncPinnedHostFilterState()
    }

    private func togglePinnedHost(_ host: PinnedHost) {
        settings.togglePinnedHostSelection(host.host)
        syncPinnedHostFilterState()
    }

    private func resetFilters() {
        filter = FlowFilter()
        settings.clearPinnedHostSelections()
        syncPinnedHostFilterState()
    }

    private func syncPinnedHostFilterState() {
        let activeHosts = settings.pinnedHosts
            .filter { $0.isActive }
            .map(\.host)
        filter.updateActivePinnedHosts(activeHosts)
    }

    private var rulesSheet: some View {
        RulesManagerView(
            viewModel: rulesViewModel,
            onUpdate: { key, body, status, headers, enabled in
                viewModel.updateRule(
                    key: key,
                    body: body,
                    status: status,
                    headers: headers,
                    isEnabled: enabled
                )
            },
            onDelete: { key in
                viewModel.deleteRule(key: key)
            },
            onCreate: { host, path in
                viewModel.createRule(host: host, path: path)
            },
            onSetRuleEnabled: { key, enabled in
                viewModel.setRule(key, enabled: enabled)
            }
        )
    }

    private var collectionsSheet: some View {
        CollectionsManagerView(viewModel: viewModel)
    }

    private var mapSheet: some View {
        NavigationStack {
            MapEditorView(
                viewModel: mapEditorViewModel,
                colors: colors,
                allowRequestEditing: false,
                showsRequestEditor: false,
                actions: MapEditorActions(
                    onSave: {
                        guard let payload = mapEditorViewModel.payload(
                            defaultStatus: viewModel.selectedFlow?.response?.status ?? 200
                        ) else { return }
                        viewModel.mapResponse(
                            body: payload.responseBody,
                            status: payload.responseStatus,
                            headers: payload.responseHeaders
                        )
                        mapEditorViewModel.markSynced()
                    },
                    onClose: {
                        showMapSheet = false
                    }
                ),
                isSelectionAvailable: viewModel.selectedFlowID != nil,
                titlePrefix: "Map Local"
            )
            .onAppear {
                if let flow = viewModel.selectedFlow {
                    mapEditorViewModel.load(flow: flow)
                } else {
                    mapEditorViewModel.clear()
                }
            }
        }
        .frame(minWidth: 1280, minHeight: 800, maxHeight: 800)
    }

    private var retrySheet: some View {
        NavigationStack {
            MapEditorView(
                viewModel: retryEditorViewModel,
                colors: colors,
                allowRequestEditing: true,
                showsResponseEditor: false,
                actions: MapEditorActions(
                    saveLabel: "Retry",
                    saveIcon: "arrow.clockwise",
                    onSave: {
                        guard let payload = retryEditorViewModel.retryPayload() else { return }
                        viewModel.retryFlow(with: payload)
                        retryEditorViewModel.markSynced()
                        showRetrySheet = false
                    },
                    closeLabel: "Close",
                    closeIcon: "xmark",
                    onClose: { showRetrySheet = false }
                ),
                isSelectionAvailable: retryEditorViewModel.hasSelection,
                titlePrefix: "Retry"
            )
        }
        .frame(minWidth: 1280, minHeight: 800)
    }
    
    private var breakpointSheet: some View {
        NavigationStack {
            MapEditorView(
                viewModel: breakpointEditorViewModel,
                colors: colors,
                allowRequestEditing: activeBreakpointPhase == .request,
                showsRequestEditor: activeBreakpointPhase == .request,
                showsResponseEditor: activeBreakpointPhase == .response,
                actions: MapEditorActions(
                    saveLabel: "Continue",
                    saveIcon: "play.circle.fill",
                    onSave: {
                        viewModel.continueActiveBreakpoint(using: breakpointEditorViewModel)
                    },
                    closeLabel: "Skip",
                    closeIcon: "forward.end",
                    onClose: {
                        viewModel.skipActiveBreakpoint()
                    }
                ),
                isSelectionAvailable: breakpointEditorViewModel.hasSelection,
                titlePrefix: "Breakpoint"
            )
        }
        .frame(minWidth: 1100, minHeight: 720)
    }

    private func sortedRules() -> [MapRule] {
        viewModel.rules.values.sorted(by: { $0.key < $1.key })
    }

    private var inspectorMinHeight: CGFloat { 0 }
    private var inspectorDragActivationHeight: CGFloat { 10 }

    private func inspectorDragGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture()
            .updating($inspectorDrag) { value, state, _ in
                state = -value.translation.height
            }
            .onEnded { value in
                let delta = -value.translation.height
                var newHeight = inspectorHeight + delta
                newHeight = min(maxHeight, max(inspectorMinHeight, newHeight))

                let shouldClose = value.translation.height > 90 && newHeight <= inspectorMinHeight + 20
                if shouldClose {
                    viewModel.selectedFlowID = nil
                } else {
                    inspectorHeight = newHeight
                }
            }
    }
}

// MARK: - Header

private struct InspectorHeaderBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
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

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FRTM Proxy")
                    .font(DesignSystem.Fonts.mono(26, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text("Sniffa, ispeziona e mappa le richieste di rete in tempo reale.")
                    .font(DesignSystem.Fonts.mono(13, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            StatusPill(isRunning: isRunning, colors: colors)

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

// MARK: - Flow explorer (filters + table)

private struct FlowExplorerSection: View {
    @Binding var filter: FlowFilter
    let flows: [MitmFlow]
    let clientIPs: [String]
    @Binding var selection: String?
    let colors: DesignSystem.ColorPalette
    let emptyMessage: String
    let pinnedHosts: [PinnedHost]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onResetFilters: () -> Void
    let onMapLocal: (MitmFlow) -> Void
    let onEditRetry: (MitmFlow) -> Void
    let onPinHost: (String) -> Void
    let onUnpinHost: (String) -> Void
    let onFilterDevice: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowFiltersView(
                filter: $filter,
                colors: colors,
                pinnedHosts: pinnedHosts,
                clientIPs: clientIPs,
                onReset: onResetFilters,
                onTogglePinnedHost: onTogglePinnedHost,
                onRemovePinnedHost: onRemovePinnedHost
            )
            FlowTableView(
                flows: flows,
                selection: $selection,
                emptyMessage: emptyMessage,
                colors: colors,
                pinnedHostnames: Set(pinnedHosts.map(\.host)),
                onMapLocal: onMapLocal,
                onEditRetry: onEditRetry,
                onPinHost: onPinHost,
                onUnpinHost: onUnpinHost,
                onFilterDevice: onFilterDevice
            )
            .frame(minHeight: 120, idealHeight: 360, maxHeight: .infinity)
        }
    }
}

private struct FlowFiltersView: View {
    @Binding var filter: FlowFilter
    let colors: DesignSystem.ColorPalette
    let pinnedHosts: [PinnedHost]
    let clientIPs: [String]
    let onReset: () -> Void
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SearchField(text: $filter.searchText, placeholder: "Search: keywords, host:, method:, status:, type:, device: (use -term to exclude)", colors: colors)
                ControlButton(title: "Reset", systemImage: "arrow.uturn.left", style: .ghost(colors), disabled: !hasCustomFilters) {
                    onReset()
                }
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

// MARK: - Flow inspector panel

private struct FlowInspectorPanel: View {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let displayHeight: CGFloat
    let maxHeight: CGFloat
    let onMapLocal: () -> Void
    let onCopyUrl: () -> Void
    let onCopyCurl: () -> Void
    let onCopyBody: () -> Void
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?

    var body: some View {
        let offset = max(0, maxHeight - displayHeight)

        VStack(spacing: 0) {
            Spacer().frame(height: offset)
            panelContent
        }
        .frame(minHeight:0,  maxHeight: maxHeight, alignment: .bottom)
        .padding(.horizontal, 2)
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(colors.border.opacity(0.8))
                .frame(width: 42, height: 4)
                .padding(.top, 8)

            FlowSplitInspector(
                flow: flow,
                colors: colors,
                onMapLocal: onMapLocal,
                onCopyUrl: onCopyUrl,
                onCopyCurl: onCopyCurl,
                onCopyBody: onCopyBody,
                isRequestBreakpointEnabled: isRequestBreakpointEnabled,
                isResponseBreakpointEnabled: isResponseBreakpointEnabled,
                onToggleBreakpoint: onToggleBreakpoint
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.surface)
                .shadow(color: Color.black.opacity(0.25), radius: 28, y: -6)
        )
    }
}
