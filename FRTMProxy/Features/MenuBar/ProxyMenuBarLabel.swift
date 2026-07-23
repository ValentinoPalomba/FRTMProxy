import AppKit
import SwiftUI

struct ProxyMenuBarLabel: View {
    let isRunning: Bool

    var body: some View {
        Image(nsImage: isRunning ? Self.runningIcon : Self.stoppedIcon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel(isRunning ? "Proxy running" : "Proxy stopped")
    }

    private static let runningIcon = makeIcon(isRunning: true)
    private static let stoppedIcon = makeIcon(isRunning: false)

    private static func makeIcon(isRunning: Bool) -> NSImage {
        let iconSize: CGFloat = 18
        let image = NSImage(
            size: NSSize(width: iconSize, height: iconSize),
            flipped: false
        ) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x, y: iconSize - y)
            }

            let color = NSColor.black.withAlphaComponent(isRunning ? 1 : 0.5)
            color.setStroke()
            color.setFill()

            let traffic = NSBezierPath()
            traffic.lineWidth = 1.6
            traffic.lineCapStyle = .round
            traffic.lineJoinStyle = .round
            traffic.move(to: point(1.5, 5))
            traffic.line(to: point(5.5, 5))
            traffic.line(to: point(8, 7.5))
            traffic.move(to: point(1.5, 11))
            traffic.line(to: point(5.5, 11))
            traffic.line(to: point(8, 8.5))
            traffic.move(to: point(16.5, 5))
            traffic.line(to: point(12.5, 5))
            traffic.line(to: point(10, 7.5))
            traffic.move(to: point(16.5, 11))
            traffic.line(to: point(12.5, 11))
            traffic.line(to: point(10, 8.5))
            traffic.stroke()

            let capsule = NSBezierPath()
            capsule.lineWidth = 2.7
            capsule.lineCapStyle = .round
            capsule.move(to: point(5.25, 15))
            capsule.line(to: point(12.75, 2.5))
            capsule.stroke()

            let terminalCenter = point(5.25, 15)
            let terminal = NSBezierPath(
                ovalIn: NSRect(
                    x: terminalCenter.x - 1.1,
                    y: terminalCenter.y - 1.1,
                    width: 2.2,
                    height: 2.2
                )
            )

            if isRunning {
                terminal.fill()
            } else {
                terminal.lineWidth = 1.2
                terminal.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
