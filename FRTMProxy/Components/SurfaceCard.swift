import SwiftUI

struct SurfaceCard: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Color.white
    var stroke: Color = Color.gray.opacity(0.25)
    var shadowOpacity: Double = 0.14

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 18, y: 8)
            )
    }
}

extension View {
    func surfaceCard(
        radius: CGFloat = 14,
        fill: Color = Color.white,
        stroke: Color = Color.gray.opacity(0.25),
        shadowOpacity: Double = 0.18
    ) -> some View {
        modifier(SurfaceCard(radius: radius, fill: fill, stroke: stroke, shadowOpacity: shadowOpacity))
    }
}
