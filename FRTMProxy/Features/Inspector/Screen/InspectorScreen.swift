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
    @State private var showCommandPalette = false
    @State private var filter = FlowFilter()
    @State private var activeBreakpointPhase: FlowBreakpointPhase = .request
    @State private var filteredFlows: [MitmFlow] = []
    @State private var availableClientIPs: [String] = []
    @State private var filterUpdateTask: Task<Void, Never>?
    @State private var lastSearchText: String = ""

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
        let trafficProfiles = TrafficProfileLibrary.presets

        let content = VStack(spacing: 16) {
            InspectorHeaderBar(
                colors: colors,
                isRunning: viewModel.isRunning,
                lastFlow: viewModel.flows.last,
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
                onStart: {
                    Task { @MainActor in
                        await viewModel.startProxy()
                    }
                },
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
                        emptyMessage: viewModel.flows.isEmpty ? "Waiting for traffic..." : "No results for the current filters",
                        pinnedHosts: settings.pinnedHosts,
                        pinnedApps: settings.pinnedApps,
                        onTogglePinnedHost: { togglePinnedHost($0) },
                        onRemovePinnedHost: { removePinnedHost($0) },
                        onTogglePinnedApp: { togglePinnedApp($0) },
                        onRemovePinnedApp: { removePinnedApp($0) },
                        onResetFilters: resetFilters,
                        onMapLocal: { flow in openMapEditor(flow: flow) },
                        onEditRetry: { flow in openRetryEditor(for: flow) },
                        onPinHost: { pinHost(host: $0) },
                        onUnpinHost: { removePinnedHost(byHostName: $0) },
                        onPinApp: { pinApp(app: $0) },
                        onUnpinApp: { unpinApp(appID: $0) },
                        onFilterApp: { filterApp(app: $0) },
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
                        .onboardingTarget(.inspectFlow)
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
            let searchText = filter.searchText
            let searchChanged = searchText != lastSearchText
            lastSearchText = searchText
            updateFilteredFlows(debounced: searchChanged)
        }
        .onDisappear {
            filterUpdateTask?.cancel()
        }

        return contentWithFiltering
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    actions: commandPaletteActions,
                    colors: colors
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .overlay {
            ShortcutHost(
                isRunning: viewModel.isRunning,
                hasSelection: selectedFlow != nil,
                onToggleProxy: toggleProxy,
                onClear: viewModel.clear,
                onOpenCommandPalette: { showCommandPalette = true },
                onMapLocal: openMapEditor,
                onRetry: {
                    if let flow = selectedFlow {
                        openRetryEditor(for: flow)
                    }
                },
                onCopyUrl: { ClipboardHelper.copy(selectedFlow?.request?.url) },
                onCopyCurl: { ClipboardHelper.copy(selectedFlow?.curlString) }
            )
        }
        .animation(.easeOut(duration: 0.18), value: showCommandPalette)
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
            syncPinnedAppFilterState()
        }
        .onChange(of: settings.pinnedHosts) { _, _ in
            syncPinnedHostFilterState()
        }
        .onChange(of: settings.pinnedApps) { _, _ in
            syncPinnedAppFilterState()
        }
    }

    private func updateFilteredFlows() {
        updateFilteredFlows(debounced: false)
    }

    private func updateFilteredFlows(debounced: Bool) {
        let flowsSnapshot = viewModel.flows
        let filterSnapshot = filter

        filterUpdateTask?.cancel()
        filterUpdateTask = Task.detached(priority: .userInitiated) {
            if debounced {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }

            let filtered = filterSnapshot.apply(to: flowsSnapshot)
            let clientIPs = Array(
                Set(flowsSnapshot.map(\.clientIP).filter { !$0.isEmpty })
            ).sorted()

            await MainActor.run {
                guard !Task.isCancelled else { return }
                filteredFlows = filtered
                availableClientIPs = clientIPs
            }
        }
    }

    private func toggleProxy() {
        if viewModel.isRunning {
            viewModel.stopProxy()
        } else {
            Task { @MainActor in
                await viewModel.startProxy()
            }
        }
    }

    private var commandPaletteActions: [CommandPaletteAction] {
        let hasSelection = selectedFlow != nil
        return [
            CommandPaletteAction(
                title: "Start Proxy",
                subtitle: "Start the embedded mitmproxy",
                systemImage: "play.fill",
                shortcut: "⌘⌥P",
                keywords: ["start", "proxy", "mitm"],
                isEnabled: !viewModel.isRunning
            ) {
                Task { @MainActor in
                    await viewModel.startProxy()
                }
            },
            CommandPaletteAction(
                title: "Stop Proxy",
                subtitle: "Stop capturing traffic",
                systemImage: "stop.fill",
                shortcut: "⌘⌥P",
                keywords: ["stop", "proxy"],
                isEnabled: viewModel.isRunning
            ) {
                viewModel.stopProxy()
            },
            CommandPaletteAction(
                title: "Clear Flows",
                subtitle: "Remove all captured traffic",
                systemImage: "trash",
                shortcut: "⌘⌥K",
                keywords: ["clear", "reset", "flows"]
            ) {
                viewModel.clear()
            },
            CommandPaletteAction(
                title: "Open Rules",
                subtitle: "Manage map local rules",
                systemImage: "slider.horizontal.3",
                keywords: ["rules", "map", "local"]
            ) {
                showRulesSheet = true
            },
            CommandPaletteAction(
                title: "Open Breakpoints",
                subtitle: "Manage breakpoint rules",
                systemImage: "record.circle",
                keywords: ["breakpoints", "pause", "intercept"]
            ) {
                showBreakpointsManager = true
            },
            CommandPaletteAction(
                title: "Open Collections",
                subtitle: "Manage map local collections",
                systemImage: "folder",
                keywords: ["collections", "map", "rules"]
            ) {
                showCollectionsSheet = true
            },
            CommandPaletteAction(
                title: "Open Device Setup",
                subtitle: "Pair a simulator or device",
                systemImage: "qrcode",
                keywords: ["device", "qr", "pair"]
            ) {
                showDeviceConnectSheet = true
            },
            CommandPaletteAction(
                title: "Map Local (Selected Flow)",
                subtitle: "Create a local response for the selected flow",
                systemImage: "pencil.and.outline",
                shortcut: "⌘⌥M",
                keywords: ["map", "local", "mock"],
                isEnabled: hasSelection
            ) {
                openMapEditor()
            },
            CommandPaletteAction(
                title: "Retry Request (Selected Flow)",
                subtitle: "Replay the selected request",
                systemImage: "arrow.clockwise",
                shortcut: "⌘⌥R",
                keywords: ["retry", "replay"],
                isEnabled: hasSelection
            ) {
                if let flow = selectedFlow {
                    openRetryEditor(for: flow)
                }
            },
            CommandPaletteAction(
                title: "Copy URL",
                subtitle: "Copy selected flow URL",
                systemImage: "doc.on.doc",
                shortcut: "⌘⌥U",
                keywords: ["copy", "url"],
                isEnabled: hasSelection
            ) {
                ClipboardHelper.copy(selectedFlow?.request?.url)
            },
            CommandPaletteAction(
                title: "Copy cURL",
                subtitle: "Copy selected flow as cURL",
                systemImage: "terminal",
                shortcut: "⌘⌥Y",
                keywords: ["copy", "curl"],
                isEnabled: hasSelection
            ) {
                ClipboardHelper.copy(selectedFlow?.curlString)
            }
        ]
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
        settings.clearPinnedAppSelections()
        syncPinnedHostFilterState()
        syncPinnedAppFilterState()
    }

    private func syncPinnedHostFilterState() {
        let activeHosts = settings.pinnedHosts
            .filter { $0.isActive }
            .map(\.host)
        filter.updateActivePinnedHosts(activeHosts)
    }

    private func syncPinnedAppFilterState() {
        let activeApps = settings.pinnedApps
            .filter { $0.isActive }
            .map(\.appID)
        filter.updateActivePinnedApps(activeApps)
    }

    private func togglePinnedApp(_ app: PinnedApp) {
        settings.togglePinnedAppSelection(app.appID)
        syncPinnedAppFilterState()
    }

    private func removePinnedApp(_ app: PinnedApp) {
        settings.unpinApp(app.appID)
        syncPinnedAppFilterState()
    }

    private func pinApp(app: FlowClientApp) {
        settings.pinApp(app)
        syncPinnedAppFilterState()
    }

    private func unpinApp(appID: String) {
        settings.unpinApp(appID)
        syncPinnedAppFilterState()
    }

    private func filterApp(app: FlowClientApp) {
        settings.pinApp(app)
        settings.activateOnlyPinnedApp(app.id)
        syncPinnedAppFilterState()
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
