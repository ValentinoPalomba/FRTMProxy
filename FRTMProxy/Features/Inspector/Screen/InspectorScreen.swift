import SwiftUI

struct InspectorScreen: View {
    @ObservedObject var viewModel: ProxyViewModel
    @ObservedObject var rulesViewModel: MapRuleViewModel
    @StateObject private var mapEditorViewModel = MapEditorViewModel()
    @StateObject private var retryEditorViewModel = MapEditorViewModel()
    @StateObject private var breakpointEditorViewModel = MapEditorViewModel()
    @StateObject private var composerViewModel = RequestComposerViewModel()

    @State private var showMapSheet = false
    @State private var showRulesSheet = false
    @State private var showCollectionsSheet = false
    @State private var showRetrySheet = false
    @State private var showBreakpointSheet = false
    @State private var showBreakpointsManager = false
    @State private var showDeviceConnectSheet = false
    @State private var showCommandPalette = false
    @State private var showComposerSheet = false
    @State private var showScriptsSheet = false
    @State private var compareFlowID: String?
    @State private var filter = FlowFilter()
    @State private var activeBreakpointPhase: FlowBreakpointPhase = .request
    @State private var filteredFlows: [MitmFlow] = []
    @State private var availableClientIPs: [String] = []
    @State private var filterUpdateTask: Task<Void, Never>?
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
                onShowRules: { showRulesSheet = true },
                onShowBreakpoints: { showBreakpointsManager = true },
                onShowCollections: { showCollectionsSheet = true },
                onShowDeviceConnect: { showDeviceConnectSheet = true },
                onShowComposer: { openComposer() },
                onShowScripts: { showScriptsSheet = true },
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
                onMapLocalTap: { showRulesSheet = true },
                onCollectionsTap: { showCollectionsSheet = true },
                onBreakpointsTap: { showBreakpointsManager = true },
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

        let withSheets1 = withOverlays
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

        let withSheets2 = withSheets1
            .sheet(isPresented: $showComposerSheet) {
                RequestComposerView(
                    viewModel: composerViewModel,
                    colors: colors,
                    proxyPort: viewModel.isRunning ? viewModel.activePort : nil,
                    onClose: { showComposerSheet = false }
                )
                .frame(minWidth: 900, minHeight: 620)
            }
            .sheet(isPresented: $showScriptsSheet) {
                ScriptsManagerView(
                    scripts: $viewModel.scripts,
                    onSave: { _ in viewModel.persistScripts() },
                    onClose: { showScriptsSheet = false }
                )
                .environmentObject(settings)
            }

        return withSheets2
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
        .onChange(of: showRulesSheet) { _, shown in
            if shown {
                rulesViewModel.load(sortedRules())
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

    private func openComposer() {
        if let flow = selectedFlow {
            composerViewModel.loadFromFlow(flow)
        }
        showComposerSheet = true
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

private struct InspectorBottomBar: View {
    let colors: DesignSystem.ColorPalette
    let isRunning: Bool
    let activePort: Int
    let totalFlowCount: Int
    let shownFlowCount: Int
    let isMacProxyActive: Bool
    let activeTrafficProfile: TrafficProfile
    let activeMapLocalCount: Int
    let activeCollectionsCount: Int
    let activeBreakpointsCount: Int
    let compareFlowID: String?
    let onClear: () -> Void
    let onOpenCommandPalette: () -> Void
    let onMapLocalTap: () -> Void
    let onCollectionsTap: () -> Void
    let onBreakpointsTap: () -> Void
    let onClearCompare: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            statusSection

            Spacer(minLength: DesignSystem.Spacing.md)

            modifiersSection

            actionsSection
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            Rectangle()
                .fill(colors.surface.opacity(0.97))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(colors.border.opacity(0.9))
                        .frame(height: 1)
                }
        )
    }

    private var statusSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                statusDot
                Text(isRunning ? "Running :\(String(activePort))" : "Stopped")
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(isRunning ? colors.textPrimary : colors.textSecondary)
            }
            .help(statusHelp)

            statusDivider

            Text(flowCountText)
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textSecondary)
                .help("\(totalFlowCount) captured · \(shownFlowCount) shown with current filters")
        }
        .fixedSize()
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .strokeBorder(colors.accent, lineWidth: 1.5)
                .frame(width: DesignSystem.Metrics.scaled(14), height: DesignSystem.Metrics.scaled(14))
                .opacity(isMacProxyActive ? 1 : 0)
            Circle()
                .fill(isRunning ? colors.success : colors.textSecondary.opacity(0.5))
                .frame(width: DesignSystem.Metrics.scaled(8), height: DesignSystem.Metrics.scaled(8))
        }
        .frame(width: DesignSystem.Metrics.scaled(16), height: DesignSystem.Metrics.scaled(16))
    }

    private var statusHelp: String {
        var text = isRunning ? "Proxy listening on port \(String(activePort))" : "Proxy stopped"
        if isMacProxyActive {
            text += " · Also routing this Mac"
        }
        return text
    }

    private var flowCountText: String {
        shownFlowCount == totalFlowCount ? "\(totalFlowCount) flows" : "\(shownFlowCount) / \(totalFlowCount) flows"
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(colors.border)
            .frame(width: 1, height: DesignSystem.Metrics.scaled(12))
    }

    @ViewBuilder
    private var modifiersSection: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TrafficProfileStatusItem(profile: activeTrafficProfile, colors: colors)

            if activeMapLocalCount > 0 {
                ModifierStatusItem(title: "Map Local", systemImage: "app.badge", count: activeMapLocalCount, tint: colors.accent, colors: colors)
                    .onTapGesture { onMapLocalTap() }
            }
            if activeCollectionsCount > 0 {
                ModifierStatusItem(title: "Collections", systemImage: "folder", count: activeCollectionsCount, tint: colors.accentSecondary, colors: colors)
                    .onTapGesture { onCollectionsTap() }
            }
            if activeBreakpointsCount > 0 {
                ModifierStatusItem(title: "Breakpoints", systemImage: "record.circle", count: activeBreakpointsCount, tint: colors.danger, colors: colors)
                    .onTapGesture { onBreakpointsTap() }
            }
            if compareFlowID != nil {
                ModifierStatusItem(title: "Compare", systemImage: "square.on.square", count: 0, tint: colors.accentSecondary, colors: colors, customLabel: "Compare: active")
                    .onTapGesture { onClearCompare() }
                    .help("Tap to exit compare mode")
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ControlButton(title: "Clear", systemImage: "trash", style: .ghost(colors), disabled: totalFlowCount == 0) {
                onClear()
            }
            commandPaletteButton
        }
    }

    private var commandPaletteButton: some View {
        Button(action: onOpenCommandPalette) {
            Image(systemName: "keyboard")
                .font(.system(size: DesignSystem.Metrics.scaled(13), weight: .semibold))
                .frame(width: DesignSystem.Metrics.scaled(34), height: DesignSystem.Metrics.scaled(34))
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .foregroundStyle(colors.textPrimary)
        }
        .buttonStyle(.plain)
        .help("Command Palette (⌘K)")
        .accessibilityLabel(Text("Command Palette"))
    }
}

private struct TrafficProfileStatusItem: View {
    let profile: TrafficProfile
    let colors: DesignSystem.ColorPalette

    private var tint: Color {
        profile.isDisabled ? colors.textSecondary : colors.warning
    }

    private var label: String {
        profile.isDisabled ? "Profile: Off" : "Profile: \(profile.name)"
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: profile.systemImageName)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text(label)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ModifierStatusItem: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color
    let colors: DesignSystem.ColorPalette
    var customLabel: String? = nil

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: DesignSystem.Metrics.scaled(11), weight: .semibold))
            Text(customLabel ?? "\(title): \(count)")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
        )
    }
}
