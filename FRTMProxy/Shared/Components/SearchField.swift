import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let colors: DesignSystem.ColorPalette
    var size: ProxyTextFieldStyle.Size = .compact
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textFieldStyle(
                    ProxyTextFieldStyle(
                        palette: colors,
                        leadingIcon: "magnifyingglass",
                        size: size,
                        trailingAccessoryWidth: text.isEmpty ? 0 : DesignSystem.Metrics.scaled(24)
                    )
                )
                .focusRing(colors, isActive: isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.textSecondary)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear search")
                .padding(.trailing, DesignSystem.Spacing.md)
            }
        }
        .frame(height: DesignSystem.Metrics.scaled(34))
    }
}
