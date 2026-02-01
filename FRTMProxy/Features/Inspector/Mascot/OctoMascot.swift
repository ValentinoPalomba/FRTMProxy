import SwiftUI
import AppKit

struct OctoPixelBadge: View {
    let colors: DesignSystem.ColorPalette
    let state: OctoState
    let embedded: Bool
    @State private var frames: [NSImage?] = []

    private let fps: Double = 8

    var body: some View {
        TimelineView(.animation) { context in
            let image = currentFrame(at: context.date)
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: 64, height: 58)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(embedded ? Color.clear : colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(embedded ? Color.clear : colors.border.opacity(0.7), lineWidth: 1)
                )
        )
        .onAppear {
            if frames.isEmpty {
                frames = OctoSpriteFrames.load()
            }
        }
    }

    private func currentFrame(at date: Date) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        let range = stateFrameRange
        let upper = min(range.upperBound, frames.count - 1)
        let lower = min(range.lowerBound, upper)
        let count = upper - lower + 1
        guard count > 0 else { return nil }
        let index = lower + (Int(date.timeIntervalSinceReferenceDate * fps) % count)
        if let frame = frames[index] {
            return frame
        }
        for fallback in lower...upper {
            if let frame = frames[fallback] {
                return frame
            }
        }
        return frames.compactMap { $0 }.first
    }

    private var stateFrameRange: ClosedRange<Int> {
        switch state {
        case .idle:
            return 0...3
        case .running:
            return 4...17
        case .error:
            return 18...34
        }
    }
}

enum OctoState {
    case idle
    case running
    case error
}

private enum OctoSpriteFrames {
    private static let frameCount = 35

    static func load() -> [NSImage?] {
        var loaded = Array<NSImage?>(repeating: nil, count: frameCount)
        for index in 0..<frameCount {
            let name = "octo_\(index)"
            if let image = NSImage(named: name) {
                loaded[index] = image
            }
        }
        return loaded
    }
}
