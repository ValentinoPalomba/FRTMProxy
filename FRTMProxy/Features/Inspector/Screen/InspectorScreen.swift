import SwiftUI

struct InspectorScreen: View {
    @ObservedObject var viewModel: ProxyViewModel
    @ObservedObject var rulesViewModel: MapRuleViewModel
    @StateObject private var mapEditorViewModel = MapEditorViewModel()
    @StateObject private var retryEditorViewModel = MapEditorViewModel()
    @StateObject private var breakpointEditorViewModel = MapEditorViewModel()
    @StateObject private var composerViewModel = RequestComposerViewModel()

    @State private var presentedDestination: InspectorDestination?
    @State private var showCommandPalette = false
    @State private var selectedSessionID: UUID?
    @State private var compareFlowID: String?
    @State private var filter = FlowFilter()
    @State private var activeBreakpointPhase: FlowBreakpointPhase = .request
    @State private var filteredFlows: [MitmFlow] = []
    @State private var availableClientIPs: [String] = []
    @State private var filterWorker = InspectorFlowFilterWorker()
    @State private var filterUpdateTask: Task<Void, Never>?
    @State private var filterGeneration: UInt = 0
    @State private var workspaceExportBundle: WorkspaceBundle?
    @State private var lastSearchText: String = ""
    @State private var confirmClearTraffic = false

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var selectedFlow: MitmFlow? {
        viewModel.selectedFlow
    }

    var body: some View {
        let trafficProfiles = settings.availableTrafficProfiles

        let flowExplorer = FlowExplorerSection(
            flows: filteredFlows,
            selection: $viewModel.selectedFlowID,
            compareSelection: $compareFlowID,
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

        let content = VStack(spacing: 0) {
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
                onShowRules: { present(.mapLocalRules) },
                onShowUnifiedRules: { present(.trafficRules) },
                onShowBreakpoints: { present(.breakpoints) },
                onShowCollections: { present(.collections) },
                onShowDeviceConnect: { present(.deviceSetup) },
                onShowComposer: { openComposer() },
                onShowScripts: { present(.scripts) },
                onShowSessions: openSessions,
                onShowSelectiveCapture: { present(.selectiveCapture) },
                onShowWorkspace: openWorkspace,
                trafficProfiles: trafficProfiles,
                activeTrafficProfile: viewModel.activeTrafficProfile,
                onSelectTrafficProfile: { profile in
                    viewModel.selectTrafficProfile(profile)
                    settings.selectedTrafficProfileID = profile.id
                },
                onToggleProxy: toggleProxy
            )
            .padding(.vertical, DesignSystem.Spacing.sm)

            Group {
                if let flow = selectedFlow {
                    VSplitView {
                        flowExplorer
                        if let cFlow = compareFlow {
                            FlowDiffView(
                                flowA: flow,
                                flowB: cFlow,
                                colors: colors,
                                onClose: { compareFlowID = nil }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minHeight: inspectorPanelMinHeight, idealHeight: inspectorPanelIdealHeight)
                        } else {
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
                    }
                } else {
                    flowExplorer
                }
            }
            .frame(maxHeight: .infinity)

            InspectorBottomBar(
                colors: colors,
                isRunning: viewModel.isRunning,
                activePort: viewModel.activePort,
                totalFlowCount: viewModel.flows.count,
                shownFlowCount: filteredFlows.count,
                isMacProxyActive: settings.overrideMacOSProxy,
                activeTrafficProfile: viewModel.activeTrafficProfile,
                activeMapLocalCount: activeMapLocalCount,
                activeCollectionsCount: activeCollectionsCount,
                activeBreakpointsCount: activeBreakpointsCount,
                compareFlowID: compareFlowID,
                onClear: requestClearTraffic,
                onOpenCommandPalette: { showCommandPalette = true },
                onMapLocalTap: { present(.mapLocalRules) },
                onCollectionsTap: { present(.collections) },
                onBreakpointsTap: { present(.breakpoints) },
                onClearCompare: { compareFlowID = nil }
            )
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

        let withOverlays = contentWithFiltering
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
            .focusedValue(\.inspectorCommands, InspectorCommands(
                isRunning: viewModel.isRunning,
                hasSelection: selectedFlow != nil,
                toggleProxy: toggleProxy,
                clear: requestClearTraffic,
                openCommandPalette: { showCommandPalette = true },
                mapLocal: openMapEditor,
                retry: {
                    if let flow = selectedFlow {
                        openRetryEditor(for: flow)
                    }
                },
                copyURL: { ClipboardHelper.copy(selectedFlow?.request?.url) },
                copyCurl: { ClipboardHelper.copy(selectedFlow?.curlString) }
            ))
            .animation(.easeOut(duration: 0.18), value: showCommandPalette)

        return withOverlays
        .sheet(item: $presentedDestination, content: destinationSheet)
        .confirmationDialog(
            "Clear all captured traffic?",
            isPresented: $confirmClearTraffic,
            titleVisibility: .visible
        ) {
            Button("Clear Traffic", role: .destructive) {
                viewModel.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every flow from the current session and cannot be undone.")
        }
        .onChange(of: viewModel.rules) { _, _ in
            rulesViewModel.load(sortedRules())
        }
        .onChange(of: presentedDestination) { previous, destination in
            if destination == .mapLocalRules {
                rulesViewModel.load(sortedRules())
            }
            if previous == .workspace, destination != .workspace {
                workspaceExportBundle = nil
            }
            if previous == .breakpointEditor,
               destination != .breakpointEditor,
               viewModel.activeBreakpointHit != nil {
                viewModel.skipActiveBreakpoint()
            }
        }
        .onChange(of: viewModel.activeBreakpointHit) { _, hit in
            guard let hit,
                  let flow = viewModel.flow(withID: hit.flowID) else {
                if presentedDestination == .breakpointEditor {
                    dismissDestination()
                }
                return
            }
            openBreakpointEditor(for: flow, phase: hit.phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .inspectorNavigationRequested)) { notification in
            guard let request = notification.object as? InspectorNavigationRequest else { return }
            handleNavigationRequest(request)
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

    @ViewBuilder
    private func destinationSheet(_ destination: InspectorDestination) -> some View {
        switch destination {
        case .mapEditor:
            mapSheet
        case .mapLocalRules:
            rulesSheet
        case .trafficRules:
            UnifiedTrafficRulesManagerView(
                document: viewModel.trafficRuleDocument,
                onSave: viewModel.saveUnifiedTrafficRules,
                onClose: dismissDestination
            )
        case .collections:
            collectionsSheet
        case .retryEditor:
            retrySheet
        case .breakpointEditor:
            breakpointSheet
        case .breakpoints:
            BreakpointsManagerView(viewModel: viewModel)
        case .deviceSetup:
            DeviceConnectView(proxyPort: viewModel.activePort, proxyIsRunning: viewModel.isRunning)
                .environmentObject(settings)
        case .composer:
            RequestComposerView(
                viewModel: composerViewModel,
                colors: colors,
                proxyPort: viewModel.isRunning ? viewModel.activePort : nil,
                onClose: dismissDestination
            )
            .frame(minWidth: 900, minHeight: 620)
        case .scripts:
            ScriptsManagerView(
                scripts: $viewModel.scripts,
                onSave: { _ in viewModel.persistScripts() },
                onClose: dismissDestination
            )
            .environmentObject(settings)
        case .sessions:
            SessionBrowserView(
                sessions: viewModel.captureSessions,
                selectedSessionID: $selectedSessionID,
                colors: colors,
                loadPage: { sessionID, cursor, limit in
                    try await viewModel.loadCaptureSessionPage(
                        sessionID: sessionID,
                        after: cursor,
                        limit: limit
                    )
                },
                deleteSession: { sessionID in
                    try await viewModel.deleteCaptureSessionNow(sessionID)
                },
                setMetadata: { flowID, sessionID, note, isBookmarked in
                    try await viewModel.setCaptureFlowMetadata(
                        flowID: flowID,
                        sessionID: sessionID,
                        note: note,
                        isBookmarked: isBookmarked
                    )
                },
                closeSession: { sessionID in
                    try await viewModel.closeCaptureSessionNow(sessionID)
                },
                onOpenFlow: { flow in
                    viewModel.openStoredFlow(flow)
                    dismissDestination()
                }
            )
        case .selectiveCapture:
            SelectiveCaptureView(
                proxyPort: viewModel.activePort,
                proxyIsRunning: viewModel.isRunning,
                colors: colors,
                onClose: dismissDestination
            )
        case .workspace:
            WorkspaceManagerView(
                exportBundle: workspaceExportBundle,
                onImport: viewModel.applyWorkspaceBundle
            )
        }
    }

    private func present(_ destination: InspectorDestination) {
        presentedDestination = destination
    }

    private func dismissDestination() {
        presentedDestination = nil
    }

    private func openSessions() {
        selectedSessionID = viewModel.activeCaptureSessionID ?? viewModel.captureSessions.first?.id
        present(.sessions)
    }

    private func handleNavigationRequest(_ request: InspectorNavigationRequest) {
        switch request {
        case .sessions:
            openSessions()
        case .selectiveCapture:
            present(.selectiveCapture)
        case .deviceSetup:
            present(.deviceSetup)
        case .trafficRules:
            present(.trafficRules)
        case .mapLocalRules:
            present(.mapLocalRules)
        case .breakpoints:
            present(.breakpoints)
        case .collections:
            present(.collections)
        case .composer:
            openComposer()
        case .scripts:
            present(.scripts)
        case .workspace:
            openWorkspace()
        }
    }

    private func updateFilteredFlows() {
        updateFilteredFlows(debounced: false)
    }

    private func updateFilteredFlows(debounced: Bool) {
        filterUpdateTask?.cancel()
        filterGeneration &+= 1
        let generation = filterGeneration
        let flows = viewModel.flows
        let filter = filter
        let worker = filterWorker
        filterUpdateTask = Task {
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            guard let projection = try? await worker.project(flows: flows, filter: filter) else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled, generation == filterGeneration else { return }
                if filteredFlows != projection.flows {
                    filteredFlows = projection.flows
                }
                if availableClientIPs != projection.clientIPs {
                    availableClientIPs = projection.clientIPs
                }
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

    private func requestClearTraffic() {
        guard !viewModel.flows.isEmpty else { return }
        confirmClearTraffic = true
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
                keywords: ["clear", "reset", "flows"],
                isEnabled: !viewModel.flows.isEmpty
            ) {
                requestClearTraffic()
            },
            CommandPaletteAction(
                title: "Open Traffic Rules",
                subtitle: "Mock, redirect, rewrite, block, delay, pause, or script traffic",
                systemImage: "point.3.connected.trianglepath.dotted",
                keywords: ["rules", "rewrite", "redirect", "block", "delay"]
            ) {
                present(.trafficRules)
            },
            CommandPaletteAction(
                title: "Open Rules",
                subtitle: "Manage legacy Map Local rules",
                systemImage: "slider.horizontal.3",
                keywords: ["rules", "map", "local"]
            ) {
                present(.mapLocalRules)
            },
            CommandPaletteAction(
                title: "Open Breakpoints",
                subtitle: "Manage breakpoint rules",
                systemImage: "record.circle",
                keywords: ["breakpoints", "pause", "intercept"]
            ) {
                present(.breakpoints)
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
                title: "Open Sessions",
                subtitle: "Browse persistent captures",
                systemImage: "clock.arrow.circlepath",
                keywords: ["sessions", "history", "capture"]
            ) {
                openSessions()
            },
            CommandPaletteAction(
                title: "Open Workspace",
                subtitle: "Import or export a Git-friendly debugging workspace",
                systemImage: "shippingbox",
                keywords: ["workspace", "git", "export", "import"]
            ) {
                openWorkspace()
            },
            CommandPaletteAction(
                title: "Selective Capture",
                subtitle: "Launch one app, browser, or CLI through the proxy",
                systemImage: "scope",
                keywords: ["selective", "launch", "app", "browser", "cli"]
            ) {
                present(.selectiveCapture)
            },
            CommandPaletteAction(
                title: "Open Device Setup",
                subtitle: "Pair a simulator or device",
                systemImage: "qrcode",
                keywords: ["device", "qr", "pair"]
            ) {
                present(.deviceSetup)
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

    private func openComposer() {
        if let flow = selectedFlow {
            composerViewModel.loadFromFlow(flow)
        }
        present(.composer)
    }

    private func openWorkspace() {
        workspaceExportBundle = viewModel.currentWorkspaceBundle()
        present(.workspace)
    }

    private func openMapEditor() {
        guard let flow = selectedFlow else { return }
        openMapEditor(flow: flow)
    }

    private func openMapEditor(flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        mapEditorViewModel.load(flow: flow)
        present(.mapEditor)
    }

    private func openRetryEditor(for flow: MitmFlow) {
        viewModel.selectedFlowID = flow.id
        retryEditorViewModel.load(flow: flow)
        present(.retryEditor)
    }
    
    private func openBreakpointEditor(for flow: MitmFlow, phase: FlowBreakpointPhase) {
        viewModel.selectedFlowID = flow.id
        breakpointEditorViewModel.load(flow: flow)
        activeBreakpointPhase = phase
        present(.breakpointEditor)
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
                        dismissDestination()
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
        .frame(minWidth: 1100, minHeight: 700, maxHeight: 700)
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
                        dismissDestination()
                    },
                    closeLabel: "Close",
                    closeIcon: "xmark",
                    onClose: dismissDestination
                ),
                isSelectionAvailable: retryEditorViewModel.hasSelection,
                titlePrefix: "Retry"
            )
        }
        .frame(minWidth: 1100, minHeight: 700)
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

    private var activeMapLocalCount: Int {
        viewModel.rules.values.filter(\.isEnabled).count
    }

    private var activeCollectionsCount: Int {
        viewModel.collections.filter(\.isEnabled).count
    }

    private var activeBreakpointsCount: Int {
        viewModel.breakpointRules.values.filter {
            $0.isEnabled && ($0.interceptRequest || $0.interceptResponse)
        }.count
    }

    private var compareFlow: MitmFlow? {
        guard let compareFlowID else { return nil }
        return viewModel.flow(withID: compareFlowID)
    }

    private var flowExplorerMinHeight: CGFloat { DesignSystem.Metrics.scaled(260) }
    private var inspectorPanelMinHeight: CGFloat { DesignSystem.Metrics.scaled(260) }
    private var inspectorPanelIdealHeight: CGFloat { DesignSystem.Metrics.scaled(340) }
}
