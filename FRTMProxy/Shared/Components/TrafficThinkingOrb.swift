import SwiftUI

/// SwiftUI Canvas port of thinking-orbs' MIT-licensed `working` / 64 preset.
/// Source and license: docs/licenses/thinking-orbs-LICENSE.txt.
struct TrafficThinkingOrb: View {
    let colors: DesignSystem.ColorPalette
    let isCapturing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var epoch = Date()

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isCapturing || reduceMotion || scenePhase != .active)) { timeline in
                Canvas { context, size in
                    let time = (!isCapturing || reduceMotion) ? 2 : timeline.date.timeIntervalSince(epoch) * 1.885
                    for dot in Self.dots(size: min(size.width, size.height), time: time) {
                        let rect = CGRect(x: dot.horizontalPosition - dot.radius, y: dot.verticalPosition - dot.radius,
                                          width: dot.radius * 2, height: dot.radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(colors.textPrimary.opacity(dot.opacity)))
                    }
                }
            }
            .frame(width: DesignSystem.Metrics.scaled(112), height: DesignSystem.Metrics.scaled(112))
            .accessibilityHidden(true)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Waiting for traffic")
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                Text(isCapturing ? "Requests will appear here as they arrive." : "Start capture to inspect requests.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inspector.emptyTrafficOrb")
    }

    private struct Dot {
        let horizontalPosition: Double
        let verticalPosition: Double
        let radius: Double
        let opacity: Double
    }

    private static let orbitMarks = (0..<40).map { mark in
        let angle = Double(mark) / 40 * 2 * Double.pi
        return (cosine: cos(angle), sine: sin(angle))
    }

    private static func hash(_ index: Int, salt: Double) -> Double {
        let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return value - floor(value)
    }

    private static func dots(size: Double, time: Double) -> [Dot] {
        let radius = size * 0.41
        let radiusScale = pow(size / 300, 0.6)
        let yaw = time * 0.12
        let yawCosine = cos(yaw)
        let yawSine = sin(yaw)
        var dots: [Dot] = []
        dots.reserveCapacity(516)
        for orbit in 0..<12 {
            let first = hash(orbit, salt: 1.7)
            let second = hash(orbit, salt: 5.2)
            let third = hash(orbit, salt: 8.9)
            let orbitRadius = radius * (0.45 + 0.52 * first)
            let theta = first * 2 * .pi
            let phi = acos(2 * second - 1)
            let normalX = sin(phi) * cos(theta)
            let normalY = cos(phi)
            let normalZ = sin(phi) * sin(theta)
            let length = max(1e-6, hypot(normalY, normalX))
            let basisX = -normalY / length
            let basisY = normalX / length
            let otherX = -normalZ * basisY
            let otherY = normalZ * basisX
            let otherZ = normalX * basisY - normalY * basisX
            let speed = (0.25 + 0.55 * third) * (third > 0.5 ? 1.0 : -1.0)

            func project(cosine: Double, sine: Double, particle: Bool) -> Dot {
                let pointX = (basisX * cosine + otherX * sine) * orbitRadius
                let pointY = (basisY * cosine + otherY * sine) * orbitRadius
                let pointZ = otherZ * sine * orbitRadius
                let rotatedX = pointX * yawCosine + pointZ * yawSine
                let rotatedZ = -pointX * yawSine + pointZ * yawCosine
                let rotatedY = pointY * cos(0.3) - rotatedZ * sin(0.3)
                let depth = pointY * sin(0.3) + rotatedZ * cos(0.3)
                let intensity = (depth / orbitRadius + 1) / 2
                return Dot(horizontalPosition: size / 2 + rotatedX, verticalPosition: size / 2 - rotatedY,
                           radius: max(0.3, (particle ? 1.2 + 1.6 * intensity : 0.9) * radiusScale),
                           opacity: particle ? 0.7 + 0.22 * intensity : 0.28 * 0.5 * (0.4 + 0.6 * intensity))
            }
            for mark in orbitMarks {
                dots.append(project(cosine: mark.cosine, sine: mark.sine, particle: false))
            }
            for particle in 0..<3 {
                let angle = time * speed + Double(particle) / 3 * 2 * .pi + second * 6
                dots.append(project(cosine: cos(angle), sine: sin(angle), particle: true))
            }
        }
        // All dots use one color; alpha composition is independent of depth order.
        return dots
    }
}
