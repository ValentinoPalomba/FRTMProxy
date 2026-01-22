import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .textFieldStyle(
                    ProxyTextFieldStyle(
                        palette: colors,
                        leadingIcon: "magnifyingglass"
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
                .padding(.trailing, 12)
            }
        }
    }
}
