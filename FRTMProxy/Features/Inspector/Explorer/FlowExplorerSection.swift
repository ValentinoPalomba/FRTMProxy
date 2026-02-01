import SwiftUI

struct FlowExplorerSection: View {
    @Binding var filter: FlowFilter
    let flows: [MitmFlow]
    let clientIPs: [String]
    @Binding var selection: String?
    let colors: DesignSystem.ColorPalette
    let emptyMessage: String
    let pinnedHosts: [PinnedHost]
    let pinnedApps: [PinnedApp]
    let onTogglePinnedHost: (PinnedHost) -> Void
    let onRemovePinnedHost: (PinnedHost) -> Void
    let onTogglePinnedApp: (PinnedApp) -> Void
    let onRemovePinnedApp: (PinnedApp) -> Void
    let onResetFilters: () -> Void
    let onMapLocal: (MitmFlow) -> Void
    let onEditRetry: (MitmFlow) -> Void
    let onPinHost: (String) -> Void
    let onUnpinHost: (String) -> Void
    let onPinApp: (FlowClientApp) -> Void
    let onUnpinApp: (String) -> Void
    let onFilterApp: (FlowClientApp) -> Void
    let onFilterDevice: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowFiltersView(
                filter: $filter,
                colors: colors,
                pinnedApps: pinnedApps,
                pinnedHosts: pinnedHosts,
                clientIPs: clientIPs,
                onReset: onResetFilters,
                onTogglePinnedHost: onTogglePinnedHost,
                onRemovePinnedHost: onRemovePinnedHost,
                onTogglePinnedApp: onTogglePinnedApp,
                onRemovePinnedApp: onRemovePinnedApp
            )
            .onboardingTarget(.filterResults)
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
            .frame(minHeight: 120, idealHeight: 360, maxHeight: .infinity)
            .onboardingTarget(.viewTraffic)
        }
    }
}
