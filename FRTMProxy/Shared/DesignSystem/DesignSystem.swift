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
            case "GET":     return .green
            case "POST":    return .blue
            case "PUT":     return .orange
            case "PATCH":   return .purple
            case "DELETE":  return .red
            default:        return palette.textPrimary
            }
        }

        static func palette(_ scheme: ColorScheme) -> ColorPalette {
            if scheme == .dark {
                return ColorPalette(
                    background: Color(hex: "0C121B"),
                    surface: Color(hex: "111927"),
                    surfaceElevated: Color(hex: "151E2D"),
                    accent: Color(hex: "1FD4A9"),
                    accentSecondary: Color(hex: "2CA0FF"),
                    success: Color(hex: "1FD4A9"),
                    warning: Color(hex: "F0B64B"),
                    danger: Color(hex: "F26F80"),
                    destructive: Color(hex: "FF5A76"),
                    textPrimary: Color(hex: "E7EDF6"),
                    textSecondary: Color(hex: "8C9AAF"),
                    border: Color(hex: "1E2735")
                )
            } else {
                return ColorPalette(
                    background: Color(hex: "F9F9FB"),
                    surface: Color(hex: "FFFFFF"),
                    surfaceElevated: Color(hex: "F2F3F7"),
                    accent: Color(hex: "007AFF"),
                    accentSecondary: Color(hex: "22C55E"),
                    success: Color(hex: "22C55E"),
                    warning: Color(hex: "F59E0B"),
                    danger: Color(hex: "EF4444"),
                    destructive: Color(hex: "FF3B30"),
                    textPrimary: Color(hex: "1D1D1F"),
                    textSecondary: Color(hex: "6E6E73"),
                    border: Color(hex: "EAEAEB")
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
            .system(size: Metrics.font(size), weight: weight, design: .rounded)
        }
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
