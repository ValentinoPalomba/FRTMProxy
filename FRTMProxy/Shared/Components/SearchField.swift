import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    let colors: DesignSystem.ColorPalette
    var size: ProxyTextFieldStyle.Size = .compact

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .textFieldStyle(
                    ProxyTextFieldStyle(
                        palette: colors,
                        leadingIcon: "magnifyingglass",
                        size: size
                    )
                )
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .padding(.trailing, DesignSystem.Spacing.md)
            }
        }
        .frame(height: DesignSystem.Metrics.scaled(34))
    }
}
