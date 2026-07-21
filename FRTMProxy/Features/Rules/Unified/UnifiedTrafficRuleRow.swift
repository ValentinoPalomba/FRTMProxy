import SwiftUI

struct UnifiedTrafficRuleRow: View {
    let rule: TrafficRule
    let colors: DesignSystem.ColorPalette
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            Toggle("Enable \(rule.name)", isOn: Binding(get: { rule.isEnabled }, set: onToggle))
                .labelsHidden()
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(rule.name)
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.textPrimary)
                    Text("Priority \(rule.priority)")
                        .font(DesignSystem.Fonts.mono(11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                Text(rule.matcher.compactSummary)
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(rule.actions) { action in
                        Label(action.displayName, systemImage: action.systemImage)
                            .font(.caption)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .foregroundStyle(colors.textSecondary)
                            .background(colors.surfaceElevated, in: .capsule)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(actionAccessibilityLabel)
            }
            Spacer(minLength: DesignSystem.Spacing.lg)
            HStack(spacing: DesignSystem.Spacing.xs) {
                Button("Move Rule Up", systemImage: "chevron.up", action: onMoveUp)
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveUp)
                    .buttonStyle(.pressable)
                    .hoverHighlight(colors)
                Button("Move Rule Down", systemImage: "chevron.down", action: onMoveDown)
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveDown)
                    .buttonStyle(.pressable)
                    .hoverHighlight(colors)
                Button("Edit Rule", systemImage: "pencil", action: onEdit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.pressable)
                    .hoverHighlight(colors)
                Button("Delete Rule", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.pressable)
                    .hoverHighlight(colors)
            }
            .foregroundStyle(colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(colors.surface.opacity(rule.isEnabled ? 1 : 0.55), in: .rect(cornerRadius: DesignSystem.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .strokeBorder(colors.border, lineWidth: 1)
        }
        .opacity(rule.isEnabled ? 1 : 0.65)
        .accessibilityElement(children: .contain)
    }

    private var actionAccessibilityLabel: String {
        guard !rule.actions.isEmpty else { return "No actions" }
        return "Actions: " + rule.actions.map(\.displayName).joined(separator: ", ")
    }
}
