import SwiftUI

enum ControlButtonStyle {
    case filled(DesignSystem.ColorPalette)
    case ghost(DesignSystem.ColorPalette)
    case destructive(DesignSystem.ColorPalette)
}

struct ControlButton: View {
    let title: String
    let systemImage: String
    let style: ControlButtonStyle
    let disabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    init(title: String, systemImage: String, style: ControlButtonStyle, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.disabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .font(DesignSystem.Fonts.mono(13, weight: .semibold))
            .padding(.horizontal, DesignSystem.Metrics.scaled(14))
            .padding(.vertical, DesignSystem.Metrics.scaled(9))
            .frame(minHeight: DesignSystem.Metrics.scaled(34))
            .background(background)
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10)))
            .accessibilityLabel(Text(title))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.15), value: disabled)
        .scaleEffect(disabled ? 1.0 : 1.0)
        .disabled(disabled)
    }
    
    private var background: AnyShapeStyle {
        switch style {
        case .filled(let palette):
            return AnyShapeStyle(
                palette.accent.opacity(disabled ? 0.4 : 1)
            )
        case .ghost(let palette):
            return AnyShapeStyle(palette.surface.opacity(colorScheme == .dark ? 0.75 : 1))
        case .destructive(let palette):
            return AnyShapeStyle(
                palette.destructive.opacity(disabled ? 0.35 : 1)
            )
        }
    }
    
    private var border: Color {
        switch style {
        case .filled(let palette):
            return palette.accent.opacity(disabled ? 0.35 : 0.9)
        case .ghost(let palette):
            return palette.border.opacity(0.9)
        case .destructive(let palette):
            return palette.destructive.opacity(disabled ? 0.3 : 0.8)
        }
    }
    
    private var foreground: Color {
        switch style {
        case .filled:
            return Color.black.opacity(0.9)
        case .ghost(let palette):
            return palette.textPrimary
        case .destructive:
            return Color.white
        }
    }
}

struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool
    let color: Color
    let colors: DesignSystem.ColorPalette
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? color : colors.border)
                    .frame(width: DesignSystem.Metrics.scaled(10), height: DesignSystem.Metrics.scaled(10))
                Text(title)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
            }
            .padding(.horizontal, DesignSystem.Metrics.scaled(10))
            .padding(.vertical, DesignSystem.Metrics.scaled(6))
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(isOn ? color.opacity(0.16) : colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(isOn ? color.opacity(0.9) : colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isOn)
    }
}
