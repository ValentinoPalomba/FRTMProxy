import SwiftUI

struct ProxyTextFieldStyle: TextFieldStyle {
    enum Size {
        case regular
        case compact

        var verticalPadding: CGFloat {
            switch self {
            case .regular: return DesignSystem.Metrics.scaled(10)
            case .compact: return DesignSystem.Metrics.scaled(7)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return DesignSystem.Metrics.scaled(12)
            case .compact: return DesignSystem.Metrics.scaled(10)
            }
        }
    }

    let palette: DesignSystem.ColorPalette
    var leadingIcon: String?
    var size: Size = .regular

    func _body(configuration: TextField<_Label>) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
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
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .stroke(palette.border.opacity(0.85), lineWidth: 1)
        )
    }
}
