import SwiftUI

struct FlowInspectorPanel: View {
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
        .frame(minHeight: 0, maxHeight: maxHeight, alignment: .bottom)
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
