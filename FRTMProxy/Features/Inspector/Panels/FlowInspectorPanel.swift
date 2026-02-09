import SwiftUI

struct FlowInspectorPanel: View {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onMapLocal: () -> Void
    let onCopyUrl: () -> Void
    let onCopyCurl: () -> Void
    let onCopyBody: () -> Void
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?
    let onApproveDomain: ((String) -> Void)?
    let domainApprovalStatus: DomainApprovalStatus.Status?

    var body: some View {
        FlowSplitInspector(
            flow: flow,
            colors: colors,
            onMapLocal: onMapLocal,
            onCopyUrl: onCopyUrl,
            onCopyCurl: onCopyCurl,
            onCopyBody: onCopyBody,
            isRequestBreakpointEnabled: isRequestBreakpointEnabled,
            isResponseBreakpointEnabled: isResponseBreakpointEnabled,
            onToggleBreakpoint: onToggleBreakpoint,
            onApproveDomain: onApproveDomain,
            domainApprovalStatus: domainApprovalStatus
        )
        .padding(.horizontal, DesignSystem.Metrics.scaled(12))
        .padding(.vertical, DesignSystem.Metrics.scaled(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.surface)
    }
}
