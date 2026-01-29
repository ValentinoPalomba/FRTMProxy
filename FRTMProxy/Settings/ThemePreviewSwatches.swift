import SwiftUI

struct ThemePreviewSwatches: View {
    let swatches: [Color]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(swatches.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(swatches[index])
                    .frame(width: 16, height: 28)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colors.border.opacity(0.6), lineWidth: 1)
        )
    }
}
