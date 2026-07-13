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

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, systemImage: String, style: ControlButtonStyle, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .font(DesignSystem.Fonts.sans(13, weight: .semibold))
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(minHeight: DesignSystem.Metrics.scaled(32))
            .background(backgroundView)
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering in
            guard !disabled else { return }
            withAnimation(DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .disabled(disabled)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var showHover: Bool {
        isHovering && !disabled
    }

    private var backgroundView: some View {
        ZStack {
            fillColor
            (showHover ? hoverTint : Color.clear)
        }
    }

    private var fillColor: Color {
        switch style {
        case .filled(let palette):
            return palette.accent.opacity(disabled ? 0.45 : 1)
        case .ghost(let palette):
            return palette.surface
        case .destructive(let palette):
            return palette.destructive.opacity(disabled ? 0.4 : 1)
        }
    }

    private var hoverTint: Color {
        switch style {
        case .ghost(let palette):
            return palette.textPrimary.opacity(0.06)
        case .filled, .destructive:
            return Color.white.opacity(0.12)
        }
    }

    private var border: Color {
        switch style {
        case .filled(let palette):
            return palette.accent.opacity(disabled ? 0.35 : 0.6)
        case .ghost(let palette):
            return palette.border
        case .destructive(let palette):
            return palette.destructive.opacity(disabled ? 0.3 : 0.6)
        }
    }

    private var foreground: Color {
        switch style {
        case .filled:
            return .white
        case .ghost(let palette):
            return palette.textPrimary
        case .destructive:
            return .white
        }
    }
}

struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool
    let color: Color
    let colors: DesignSystem.ColorPalette

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Circle()
                    .fill(isOn ? color : colors.textSecondary.opacity(0.6))
                    .frame(width: DesignSystem.Metrics.scaled(8), height: DesignSystem.Metrics.scaled(8))
                Text(title)
                    .font(DesignSystem.Fonts.label)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs + DesignSystem.Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? color.opacity(0.16) : colors.textPrimary.opacity(isHovering ? 0.06 : 0))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? color.opacity(0.7) : colors.border, lineWidth: 1)
            )
            .foregroundStyle(isOn ? colors.textPrimary : colors.textSecondary)
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .animation(DesignSystem.Motion.adaptive(DesignSystem.Motion.fast, reduceMotion: reduceMotion), value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
