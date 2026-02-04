import SwiftUI

struct InspectorScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore

    @ObservedObject var viewModel: ProxyViewModel
    @ObservedObject var rulesViewModel: MapRuleViewModel
    @StateObject private var mapEditorViewModel = MapEditorViewModel()
    @StateObject private var retryEditorViewModel = MapEditorViewModel()
    @StateObject private var breakpointEditorViewModel = MapEditorViewModel()

    @State private var activeSheet: ActiveSheet?
    @State private var showCommandPalette = false
    @State private var filter = FlowFilter()
    @State private var activeBreakpointPhase: FlowBreakpointPhase = .request
    @State private var filteredFlows: [MitmFlow] = []
    @State private var availableClientIPs: [String] = []
    @State private var filterUpdateTask: Task<Void, Never>?
    @State private var lastSearchText: String = ""

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var selectedFlow: MitmFlow? {
        viewModel.selectedFlow
    }

    private var trafficProfiles: [TrafficProfile] {
        TrafficProfileLibrary.presets
    }

    private enum ActiveSheet: String, Identifiable {
        case map
        case rules
        case collections
        case retry
        case breakpoint
        case breakpointsManager
        case deviceConnect

        var id: String { rawValue }
    }

    var body: some View {
        mainContent
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
            .overlay {
                commandPaletteOverlay
            }
            .overlay {
                shortcutOverlay
            }
            .animation(.easeOut(duration: 0.18), value: showCommandPalette)
            .sheet(item: $activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .onChange(of: viewModel.rules) { _, _ in
                rulesViewModel.load(sortedRules())
            }
            .onChange(of: activeSheet) { oldValue, newValue in
                if oldValue == .breakpoint && newValue != .breakpoint && viewModel.activeBreakpointHit != nil {
                    viewModel.skipActiveBreakpoint()
                }
                if newValue == .rules {
                    rulesViewModel.load(sortedRules())
                }
            }
            .onChange(of: viewModel.activeBreakpointHit) { _, hit in
                guard let hit,
                      let flow = viewModel.flow(withID: hit.flowID) else {
                    if activeSheet == .breakpoint {
                        activeSheet = nil
                    }
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

    private var mainContent: some View {
        VStack(spacing: 16) {
            headerBar
            inspectorContent
        }
    }

    private var headerBar: some View {
        InspectorHeaderBar(
            colors: colors,
            isRunning: viewModel.isRunning,
            filter: $filter,
            pinnedApps: settings.pinnedApps,
            pinnedHosts: settings.pinnedHosts,
            clientIPs: availableClientIPs,
            onTogglePinnedHost: { togglePinnedHost($0) },
            onRemovePinnedHost: { removePinnedHost($0) },
            onTogglePinnedApp: { togglePinnedApp($0) },
            onRemovePinnedApp: { removePinnedApp($0) },
            onShowRules: { present(.rules) },
            onShowBreakpoints: { present(.breakpointsManager) },
            onShowCollections: { present(.collections) },
            onShowDeviceConnect: { present(.deviceConnect) },
            trafficProfiles: trafficProfiles,
            activeTrafficProfile: viewModel.activeTrafficProfile,
            onSelectTrafficProfile: { profile in
                viewModel.selectTrafficProfile(profile)
                settings.selectedTrafficProfileID = profile.id
            },
            onToggleProxy: toggleProxy
        )
        .padding(.vertical, DesignSystem.Metrics.scaled(10))
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let flow = selectedFlow {
            selectedFlowInspector(flow)
        } else {
            flowExplorer
        }
    }

    private var flowExplorer: some View {
        FlowExplorerSection(
            flows: filteredFlows,
            selection: $viewModel.selectedFlowID,
            colors: colors,
            emptyMessage: viewModel.flows.isEmpty ? "Waiting for traffic..." : "No results for the current filters",
            pinnedHosts: settings.pinnedHosts,
            pinnedApps: settings.pinnedApps,
            onTogglePinnedHost: { togglePinnedHost($0) },
            onRemovePinnedHost: { removePinnedHost($0) },
            onTogglePinnedApp: { togglePinnedApp($0) },
            onRemovePinnedApp: { removePinnedApp($0) },
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
        .frame(minHeight: flowExplorerMinHeight)
    }

    private func selectedFlowInspector(_ flow: MitmFlow) -> some View {
        VStack(spacing: 0) {
            VSplitView {
                flowExplorer
                FlowInspectorPanel(
                    flow: flow,
                    colors: colors,
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: inspectorPanelMinHeight, idealHeight: inspectorPanelIdealHeight)
            }

            InspectorBottomBar(
                colors: colors,
                activeTrafficProfile: viewModel.activeTrafficProfile,
                activeMapLocalCount: activeMapLocalCount,
                activeCollectionsCount: activeCollectionsCount,
                activeBreakpointsCount: activeBreakpointsCount,
                onClear: viewModel.clear
            )
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
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

    private var shortcutOverlay: some View {
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
}

private extension InspectorScreen {
    // MARK: - Filtering

    func updateFilteredFlows() {
        updateFilteredFlows(debounced: false)
    }

    func updateFilteredFlows(debounced: Bool) {
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
}

private extension InspectorScreen {
    // MARK: - Proxy

    func toggleProxy() {
        if viewModel.isRunning {
            viewModel.stopProxy()
        } else {
            Task { @MainActor in
                await viewModel.startProxy()
            }
        }
    }
}

private extension InspectorScreen {
    // MARK: - Command Palette

    var commandPaletteActions: [CommandPaletteAction] {
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
                present(.rules)
            },
            CommandPaletteAction(
                title: "Open Breakpoints",
                subtitle: "Manage breakpoint rules",
                systemImage: "record.circle",
                keywords: ["breakpoints", "pause", "intercept"]
            ) {
                present(.breakpointsManager)
            },
            CommandPaletteAction(
                title: "Open Collections",
                subtitle: "Manage map local collections",
                systemImage: "folder",
                keywords: ["collections", "map", "rules"]
            ) {
                present(.collections)
            },
            CommandPaletteAction(
                title: "Open Device Setup",
                subtitle: "Pair a simulator or device",
                systemImage: "qrcode",
                keywords: ["device", "qr", "pair"]
            ) {
                present(.deviceConnect)
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
}

private extension InspectorScreen {
    // MARK: - Actions

    private func present(_ sheet: ActiveSheet) {
        activeSheet = sheet
    }

    private func dismissActiveSheet() {
        activeSheet = nil
    }

    func openMapEditor() {
        guard let flow = selectedFlow else { return }
        openMapEditor(flow: flow)
    }

    func openMapEditor(flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        mapEditorViewModel.load(flow: flow)
        present(.map)
    }

    func openRetryEditor(for flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        retryEditorViewModel.load(flow: flow)
        present(.retry)
    }
    
    func openBreakpointEditor(for flow: MitmFlow, phase: FlowBreakpointPhase) {
        viewModel.selectedFlowID = flow.id
        breakpointEditorViewModel.load(flow: flow)
        activeBreakpointPhase = phase
        present(.breakpoint)
    }

    func pinHost(host: String) {
        settings.pinHost(host)
        syncPinnedHostFilterState()
    }

    func removePinnedHost(_ host: PinnedHost) {
        settings.unpinHost(host.host)
        syncPinnedHostFilterState()
    }

    func removePinnedHost(byHostName host: String) {
        settings.unpinHost(host)
        syncPinnedHostFilterState()
    }

    func togglePinnedHost(_ host: PinnedHost) {
        settings.togglePinnedHostSelection(host.host)
        syncPinnedHostFilterState()
    }

    func syncPinnedHostFilterState() {
        let activeHosts = settings.pinnedHosts
            .filter { $0.isActive }
            .map(\.host)
        filter.updateActivePinnedHosts(activeHosts)
    }

    func syncPinnedAppFilterState() {
        let activeApps = settings.pinnedApps
            .filter { $0.isActive }
            .map(\.appID)
        filter.updateActivePinnedApps(activeApps)
    }

    func togglePinnedApp(_ app: PinnedApp) {
        settings.togglePinnedAppSelection(app.appID)
        syncPinnedAppFilterState()
    }

    func removePinnedApp(_ app: PinnedApp) {
        settings.unpinApp(app.appID)
        syncPinnedAppFilterState()
    }

    func pinApp(app: FlowClientApp) {
        settings.pinApp(app)
        syncPinnedAppFilterState()
    }

    func unpinApp(appID: String) {
        settings.unpinApp(appID)
        syncPinnedAppFilterState()
    }

    func filterApp(app: FlowClientApp) {
        settings.pinApp(app)
        settings.activateOnlyPinnedApp(app.id)
        syncPinnedAppFilterState()
    }
}

private extension InspectorScreen {
    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .map:
            mapSheet
        case .rules:
            rulesSheet
        case .collections:
            collectionsSheet
        case .retry:
            retrySheet
        case .breakpoint:
            breakpointSheet
        case .breakpointsManager:
            BreakpointsManagerView(viewModel: viewModel)
        case .deviceConnect:
            DeviceConnectView(proxyPort: viewModel.activePort, proxyIsRunning: viewModel.isRunning)
                .environmentObject(settings)
        }
    }

    var rulesSheet: some View {
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

    var collectionsSheet: some View {
        CollectionsManagerView(viewModel: viewModel)
    }

    var mapSheet: some View {
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
                        dismissActiveSheet()
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

    var retrySheet: some View {
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
                        dismissActiveSheet()
                    },
                    closeLabel: "Close",
                    closeIcon: "xmark",
                    onClose: { dismissActiveSheet() }
                ),
                isSelectionAvailable: retryEditorViewModel.hasSelection,
                titlePrefix: "Retry"
            )
        }
        .frame(minWidth: 1280, minHeight: 800)
    }
    
    var breakpointSheet: some View {
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
}

private extension InspectorScreen {
    // MARK: - Derived State

    func sortedRules() -> [MapRule] {
        viewModel.rules.values.sorted(by: { $0.key < $1.key })
    }

    var activeMapLocalCount: Int {
        viewModel.rules.values.filter(\.isEnabled).count
    }

    var activeCollectionsCount: Int {
        viewModel.collections.filter(\.isEnabled).count
    }

    var activeBreakpointsCount: Int {
        viewModel.breakpointRules.values.filter {
            $0.isEnabled && ($0.interceptRequest || $0.interceptResponse)
        }.count
    }

    var flowExplorerMinHeight: CGFloat { DesignSystem.Metrics.scaled(260) }
    var inspectorPanelMinHeight: CGFloat { DesignSystem.Metrics.scaled(260) }
    var inspectorPanelIdealHeight: CGFloat { DesignSystem.Metrics.scaled(340) }
}
