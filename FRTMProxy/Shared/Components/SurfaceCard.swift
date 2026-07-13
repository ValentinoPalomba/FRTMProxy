import SwiftUI

struct SurfaceCard: ViewModifier {
    var radius: CGFloat = DesignSystem.Radius.lg
    var fill: Color = Color(nsColor: .controlBackgroundColor)
    var stroke: Color = Color(nsColor: .separatorColor)
    var shadowOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 12, y: 4)
            )
    }
}

extension View {
    func surfaceCard(
        radius: CGFloat = DesignSystem.Radius.lg,
        fill: Color = Color(nsColor: .controlBackgroundColor),
        stroke: Color = Color(nsColor: .separatorColor),
        shadowOpacity: Double = 0.12
    ) -> some View {
        modifier(SurfaceCard(radius: radius, fill: fill, stroke: stroke, shadowOpacity: shadowOpacity))
    }

    func surfaceCard(
        palette: DesignSystem.ColorPalette,
        radius: CGFloat = DesignSystem.Radius.lg,
        shadowOpacity: Double = 0.12
    ) -> some View {
        modifier(SurfaceCard(
            radius: radius,
            fill: palette.surfaceElevated,
            stroke: palette.border,
            shadowOpacity: shadowOpacity
        ))
    }
}
