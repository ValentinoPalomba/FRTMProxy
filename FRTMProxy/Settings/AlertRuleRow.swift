import SwiftUI

struct AlertRuleRow: View {
    let rule: AlertRule
    let colors: DesignSystem.ColorPalette
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: onToggle)) {
                VStack(alignment: .leading, spacing: 4) {
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

            VStack(alignment: .trailing, spacing: 8) {
                Button("Edit", systemImage: "pencil", action: onEdit)
                    .buttonStyle(.borderless)

                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colors.border.opacity(0.6), lineWidth: 1)
        )
    }
}
