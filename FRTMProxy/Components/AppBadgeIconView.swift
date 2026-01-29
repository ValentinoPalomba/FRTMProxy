import SwiftUI

struct AppBadgeIconView: View {
    let title: String
    let seed: String
    let size: CGFloat

    init(title: String, seed: String? = nil, size: CGFloat) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.seed = (seed ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        self.size = size
    }

    var body: some View {
        let base = baseColor
        RoundedRectangle(cornerRadius: max(size * 0.22, 3), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        base.opacity(0.95),
                        base.opacity(0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(size * 0.22, 3), style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .overlay {
                Text(initials)
                    .font(.system(size: max(8, size * 0.55), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(title)
    }

    private var initials: String {
        let words = title
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.isEmpty {
            return "?"
        }

        if words.count == 1 {
            let text = words[0]
            let firstTwo = text.prefix(2)
            return firstTwo.uppercased()
        }

        let first = words[0].prefix(1)
        let second = words[1].prefix(1)
        return (String(first) + String(second)).uppercased()
    }

    private var baseColor: Color {
        let hash = Self.fnv1a32(seed)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    private static func fnv1a32(_ string: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return hash
    }
}

