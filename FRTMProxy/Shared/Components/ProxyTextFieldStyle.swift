import SwiftUI

struct ProxyTextFieldStyle: TextFieldStyle {
    enum Size {
        case regular
        case compact

        var verticalPadding: CGFloat {
            switch self {
            case .regular: return 10
            case .compact: return 6
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 12
            case .compact: return 10
            }
        }
    }

    let palette: DesignSystem.ColorPalette
    var leadingIcon: String?
    var size: Size = .regular

    func _body(configuration: TextField<_Label>) -> some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .foregroundStyle(palette.textSecondary)
            }
            configuration
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, size.verticalPadding)
        .padding(.horizontal, size.horizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border.opacity(0.85), lineWidth: 1)
        )
    }
}
