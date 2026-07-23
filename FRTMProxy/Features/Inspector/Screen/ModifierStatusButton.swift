import SwiftUI

struct ModifierStatusButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color
    let colors: DesignSystem.ColorPalette
    var customLabel: String?
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ModifierStatusItem(
                title: title,
                systemImage: systemImage,
                count: count,
                tint: tint,
                colors: colors,
                customLabel: customLabel
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(customLabel ?? "\(title): \(count)"))
        .accessibilityHint(Text(help))
    }
}
