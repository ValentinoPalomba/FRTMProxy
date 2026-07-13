import Foundation
import SwiftUI

enum DesignSystem {
    enum InterfaceScale: String, CaseIterable, Identifiable, Codable {
        case small
        case medium
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .small: return "S"
            case .medium: return "M"
            case .large: return "L"
            }
        }

        var summary: String {
            switch self {
            case .small:
                return "Compact size for dense layouts."
            case .medium:
                return "Balanced size (default)."
            case .large:
                return "Comfortable size with larger spacing."
            }
        }

        var factor: CGFloat {
            switch self {
            case .small: return 0.75
            case .medium: return 0.85
            case .large: return 1.0
            }
        }

        static func option(with id: String?) -> Self {
            guard let id, let value = Self(rawValue: id) else {
                return .medium
            }
            return value
        }
    }

    enum Metrics {
        static let interfaceScaleStorageKey = "settings.interfaceScale"
        private static var interfaceScale = InterfaceScale.option(
            with: UserDefaults.standard.string(forKey: interfaceScaleStorageKey)
        )

        static var scale: CGFloat {
            interfaceScale.factor
        }

        static func applyInterfaceScale(_ option: InterfaceScale) {
            interfaceScale = option
        }

        static func scaled(_ value: CGFloat) -> CGFloat {
            value * scale
        }

        static func font(_ value: CGFloat) -> CGFloat {
            value * scale
        }

        static func cornerRadius(_ value: CGFloat) -> CGFloat {
            value * scale
        }
    }

    enum Spacing {
        static var xxs: CGFloat { Metrics.scaled(2) }
        static var xs: CGFloat { Metrics.scaled(4) }
        static var sm: CGFloat { Metrics.scaled(8) }
        static var md: CGFloat { Metrics.scaled(12) }
        static var lg: CGFloat { Metrics.scaled(16) }
        static var xl: CGFloat { Metrics.scaled(24) }
        static var xxl: CGFloat { Metrics.scaled(32) }
    }

    enum Radius {
        static var sm: CGFloat { Metrics.scaled(6) }
        static var md: CGFloat { Metrics.scaled(8) }
        static var lg: CGFloat { Metrics.scaled(12) }
        static var pill: CGFloat { 999 }
    }

    enum Motion {
        static let fast: Animation = .easeOut(duration: 0.12)
        static let base: Animation = .easeOut(duration: 0.18)
        static let slow: Animation = .easeOut(duration: 0.24)

        static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    struct ColorPalette {
        let background: Color
        let surface: Color
        let surfaceElevated: Color
        let accent: Color
        let accentSecondary: Color
        let success: Color
        let warning: Color
        let danger: Color
        let destructive: Color
        let textPrimary: Color
        let textSecondary: Color
        let border: Color
    }

    enum Colors {
        /// Returns the conventional display color for an HTTP method.
        /// Centralised here to avoid duplicated switch statements across the codebase.
        static func methodColor(_ method: String, palette: ColorPalette) -> Color {
            switch method.uppercased() {
            case "GET":     return palette.success
            case "POST":    return palette.accent
            case "PUT":     return palette.warning
            case "PATCH":   return Color(hex: "A371F7")
            case "DELETE":  return palette.danger
            default:        return palette.textSecondary
            }
        }

        static func palette(_ scheme: ColorScheme) -> ColorPalette {
            if scheme == .dark {
                return ColorPalette(
                    background: Color(hex: "0B0D10"),
                    surface: Color(hex: "14171C"),
                    surfaceElevated: Color(hex: "1B1F26"),
                    accent: Color(hex: "5E6AD2"),
                    accentSecondary: Color(hex: "4CC2B4"),
                    success: Color(hex: "3FB950"),
                    warning: Color(hex: "D29922"),
                    danger: Color(hex: "F85149"),
                    destructive: Color(hex: "F85149"),
                    textPrimary: Color(hex: "E7EAEF"),
                    textSecondary: Color(hex: "9AA3AF"),
                    border: Color(hex: "272C34")
                )
            } else {
                return ColorPalette(
                    background: Color(hex: "F7F8FA"),
                    surface: Color(hex: "FFFFFF"),
                    surfaceElevated: Color(hex: "F1F2F5"),
                    accent: Color(hex: "5A63D8"),
                    accentSecondary: Color(hex: "2FA79B"),
                    success: Color(hex: "1A7F37"),
                    warning: Color(hex: "9A6700"),
                    danger: Color(hex: "D1242F"),
                    destructive: Color(hex: "D1242F"),
                    textPrimary: Color(hex: "15181D"),
                    textSecondary: Color(hex: "5B626C"),
                    border: Color(hex: "E4E6EB")
                )
            }
        }

        static func palette(for theme: AppTheme, interfaceStyle: ColorScheme) -> ColorPalette {
            theme.palette(using: interfaceStyle)
        }
    }

    enum Fonts {
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: Metrics.font(size), weight: weight, design: .monospaced)
        }
        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: Metrics.font(size), weight: weight, design: .default)
        }

        static var title: Font { sans(17, weight: .semibold) }
        static var heading: Font { sans(15, weight: .semibold) }
        static var body: Font { sans(13) }
        static var label: Font { sans(12, weight: .medium) }
        static var caption: Font { sans(11) }
        static var monoBody: Font { mono(12) }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
