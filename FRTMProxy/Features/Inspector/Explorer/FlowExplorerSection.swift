import SwiftUI

struct FlowExplorerSection: View {
    let flows: [MitmFlow]
    @Binding var selection: String?
    let colors: DesignSystem.ColorPalette
    let emptyMessage: String
    let pinnedHosts: [PinnedHost]
    let pinnedApps: [PinnedApp]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void
    let onMapLocal: (MitmFlow) -> Void
    let onEditRetry: (MitmFlow) -> Void
    let onPinHost: (String) -> Void
    let onUnpinHost: (String) -> Void
    let onPinApp: (FlowClientApp) -> Void
    let onUnpinApp: (String) -> Void
    let onFilterApp: (FlowClientApp) -> Void
    let onFilterDevice: (String) -> Void

    var body: some View {
        FlowTableView(
            flows: flows,
            selection: $selection,
            emptyMessage: emptyMessage,
            colors: colors,
            pinnedHostnames: Set(pinnedHosts.map(\.host)),
            pinnedAppIDs: Set(pinnedApps.map(\.appID)),
            onMapLocal: onMapLocal,
            onEditRetry: onEditRetry,
            onPinHost: onPinHost,
            onUnpinHost: onUnpinHost,
            onPinApp: onPinApp,
            onUnpinApp: onUnpinApp,
            onFilterApp: onFilterApp,
            onFilterDevice: onFilterDevice
        )
        .frame(minHeight: DesignSystem.Metrics.scaled(120), idealHeight: DesignSystem.Metrics.scaled(360), maxHeight: .infinity)
        .onboardingTarget(.viewTraffic)
    }
}
