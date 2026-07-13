import SwiftUI

struct AlertRuleRow: View {
    let rule: AlertRule
    let colors: DesignSystem.ColorPalette
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: onToggle)) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(rule.name.isEmpty ? "Untitled" : rule.name)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(rule.query.isEmpty ? "—" : rule.query)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            .toggleStyle(SwitchToggleStyle())

            Spacer()

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                ControlButton(title: "Edit", systemImage: "pencil", style: .ghost(colors), action: onEdit)
                ControlButton(title: "Delete", systemImage: "trash", style: .destructive(colors), action: onDelete)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .hoverHighlight(colors, cornerRadius: DesignSystem.Radius.lg)
        .surfaceCard(palette: colors, shadowOpacity: 0)
    }
}
