import SwiftUI

struct UnifiedTrafficRuleActionsEditor: View {
    let draft: UnifiedTrafficRuleDraft
    let colors: DesignSystem.ColorPalette
    @State private var editingAction: TrafficRuleAction?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Label("Actions", systemImage: "bolt")
                        .font(DesignSystem.Fonts.title)
                    Text("Actions run from top to bottom. Mock and Block are terminal in the bridge.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Menu("Add Action", systemImage: "plus") {
                    ForEach(UnifiedTrafficRuleActionFormModel.Kind.allCases) { kind in
                        Button(kind.title) {
                            editingAction = UnifiedTrafficRuleActionFormModel.defaultAction(for: kind)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .surfaceCard(palette: colors, radius: DesignSystem.Radius.md, shadowOpacity: 0)
                .tint(colors.accent)
                .accessibilityHint("Adds a new ordered traffic action")
            }

            if draft.rule.actions.isEmpty {
                StateView(
                    kind: .empty(title: "No Actions", message: "Add at least one action before saving this rule.", systemImage: "bolt.slash"),
                    palette: colors
                )
                .frame(maxWidth: .infinity, minHeight: DesignSystem.Metrics.scaled(160))
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(draft.rule.actions) { action in
                        let index = draft.rule.actions.firstIndex { $0.id == action.id } ?? 0
                        UnifiedTrafficRuleActionRow(
                            action: action,
                            colors: colors,
                            position: index + 1,
                            canMoveUp: index > draft.rule.actions.startIndex,
                            canMoveDown: index < draft.rule.actions.index(before: draft.rule.actions.endIndex),
                            onEdit: { editingAction = action },
                            onMoveUp: { draft.moveAction(id: action.id, direction: .up) },
                            onMoveDown: { draft.moveAction(id: action.id, direction: .down) },
                            onDelete: { draft.removeAction(id: action.id) }
                        )
                    }
                }
            }
        }
        .sheet(item: $editingAction) { action in
            UnifiedTrafficRuleActionEditor(action: action, colors: colors) { updated in
                draft.upsertAction(updated)
            }
        }
    }
}

private struct UnifiedTrafficRuleActionRow: View {
    let action: TrafficRuleAction
    let colors: DesignSystem.ColorPalette
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(position, format: .number)
                .font(DesignSystem.Fonts.caption).monospacedDigit()
                .foregroundStyle(colors.textSecondary)
                .accessibilityLabel("Position \(position)")
            Image(systemName: action.systemImage)
                .foregroundStyle(colors.accent)
                .accessibilityHidden(true)
            Text(action.displayName)
                .font(DesignSystem.Fonts.body)
                .lineLimit(2)
                .help(action.displayName)
            Spacer()
            ControlButton(title: "Move Up", systemImage: "chevron.up", style: .ghost(colors), disabled: !canMoveUp, action: onMoveUp)
            ControlButton(title: "Move Down", systemImage: "chevron.down", style: .ghost(colors), disabled: !canMoveDown, action: onMoveDown)
            ControlButton(title: "Edit", systemImage: "pencil", style: .ghost(colors), action: onEdit)
            ControlButton(title: "Delete", systemImage: "trash", style: .destructive(colors), action: onDelete)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(colors.surfaceElevated, in: .rect(cornerRadius: DesignSystem.Radius.sm))
        .accessibilityElement(children: .contain)
    }
}
