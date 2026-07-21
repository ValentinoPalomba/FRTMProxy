import SwiftUI

struct UnifiedTrafficRuleActionsEditor: View {
    let draft: UnifiedTrafficRuleDraft
    @State private var editingAction: TrafficRuleAction?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Label("Actions", systemImage: "bolt")
                        .font(.headline)
                    Text("Actions run from top to bottom. Mock and Block are terminal in the bridge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Add Action", systemImage: "plus") {
                    ForEach(UnifiedTrafficRuleActionFormModel.Kind.allCases) { kind in
                        Button(kind.title) {
                            editingAction = UnifiedTrafficRuleActionFormModel.defaultAction(for: kind)
                        }
                    }
                }
                .accessibilityHint("Adds a new ordered traffic action")
            }

            if draft.rule.actions.isEmpty {
                ContentUnavailableView(
                    "No Actions",
                    systemImage: "bolt.slash",
                    description: Text("Add at least one action before saving this rule.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(draft.rule.actions.enumerated()), id: \.element.id) { index, action in
                        UnifiedTrafficRuleActionRow(
                            action: action,
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
            UnifiedTrafficRuleActionEditor(action: action) { updated in
                draft.upsertAction(updated)
            }
        }
    }
}

private struct UnifiedTrafficRuleActionRow: View {
    let action: TrafficRuleAction
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
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Position \(position)")
            Image(systemName: action.systemImage)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(action.displayName)
                .font(.body)
            Spacer()
            Button("Move Up", systemImage: "chevron.up", action: onMoveUp)
                .labelStyle(.iconOnly)
                .disabled(!canMoveUp)
            Button("Move Down", systemImage: "chevron.down", action: onMoveDown)
                .labelStyle(.iconOnly)
                .disabled(!canMoveDown)
            Button("Edit Action", systemImage: "pencil", action: onEdit)
                .labelStyle(.iconOnly)
            Button("Delete Action", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: DesignSystem.Radius.sm))
        .accessibilityElement(children: .contain)
    }
}
