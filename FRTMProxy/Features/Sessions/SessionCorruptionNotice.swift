import SwiftUI

struct SessionCorruptionNotice: View {
    let count: Int
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Label {
            Text("\(count) captured \(count == 1 ? "flow is" : "flows are") unreadable and were skipped. Other flows remain available.")
        } icon: {
            Image(systemName: "exclamationmark.shield")
        }
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.warning)
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.warning.opacity(0.1))
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}
