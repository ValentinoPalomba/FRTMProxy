import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98
    var pressedOpacity: Double = 0.92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((configuration.isPressed && !reduceMotion) ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

private struct HoverHighlight: ViewModifier {
    let palette: DesignSystem.ColorPalette
    var cornerRadius: CGFloat
    var intensity: Double
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.textPrimary.opacity(isHovering ? intensity : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering in
                withAnimation(DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
    }
}

private struct FocusRing: ViewModifier {
    let palette: DesignSystem.ColorPalette
    let isActive: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.accent, lineWidth: 1.5)
                .opacity(isActive ? 1 : 0)
        )
    }
}

extension View {
    func hoverHighlight(
        _ palette: DesignSystem.ColorPalette,
        cornerRadius: CGFloat = DesignSystem.Radius.sm,
        intensity: Double = 0.06
    ) -> some View {
        modifier(HoverHighlight(palette: palette, cornerRadius: cornerRadius, intensity: intensity))
    }

    func focusRing(
        _ palette: DesignSystem.ColorPalette,
        isActive: Bool,
        cornerRadius: CGFloat = DesignSystem.Radius.md
    ) -> some View {
        modifier(FocusRing(palette: palette, isActive: isActive, cornerRadius: cornerRadius))
    }
}
