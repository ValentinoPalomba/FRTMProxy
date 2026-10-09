import AppKit
import SwiftUI

/// Keep the embedded editor on the same palette as its native owner.
struct CodeEditorAppearance: Equatable {
    private let surface: Color
    private let elevated: Color
    private let text: Color
    private let secondary: Color
    private let accent: Color
    private let success: Color
    private let border: Color

    init(colors: DesignSystem.ColorPalette) {
        surface = colors.surface
        elevated = colors.surfaceElevated
        text = colors.textPrimary
        secondary = colors.textSecondary
        accent = colors.accent
        success = colors.success
        border = colors.border
    }

    var css: String {
        """
        html, body, .CodeMirror { background: \(rgba(surface)) !important; color: \(rgba(text)) !important; }
        .CodeMirror-gutters, .CodeMirror-dialog { background: \(rgba(elevated)) !important; border-color: \(rgba(border)) !important; }
        .CodeMirror-linenumber, .cm-comment { color: \(rgba(secondary)) !important; }
        .CodeMirror-cursor { border-left-color: \(rgba(text)) !important; }
        .CodeMirror-selected, .CodeMirror-focused .CodeMirror-selected { background: \(rgba(accent.opacity(0.22))) !important; }
        .cm-number, .cm-atom, .cm-keyword { color: \(rgba(accent)) !important; }
        .cm-string, .cm-string-2 { color: \(rgba(success)) !important; }
        .cm-property, .cm-variable, .cm-def { color: \(rgba(text)) !important; }
        .CodeMirror-dialog input { color: \(rgba(text)) !important; background: \(rgba(surface)) !important; border-color: \(rgba(border)) !important; }
        """
    }

    private func rgba(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "inherit" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return "rgba(\(red),\(green),\(blue),\(rgb.alphaComponent))"
    }
}
