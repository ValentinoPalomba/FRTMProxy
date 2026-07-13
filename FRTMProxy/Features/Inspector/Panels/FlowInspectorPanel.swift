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
            onToggleBreakpoint: onToggleBreakpoint
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.surface)
    }
}
