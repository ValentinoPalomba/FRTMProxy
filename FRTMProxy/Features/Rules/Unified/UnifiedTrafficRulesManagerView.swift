import SwiftUI

struct UnifiedTrafficRulesManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    @State private var model: UnifiedTrafficRulesViewModel
    @State private var editingRule: TrafficRule?
    @State private var pendingDeletion: TrafficRule?
    let onSave: (TrafficRuleDocument) -> Void
    let onClose: () -> Void

    init(
        document: TrafficRuleDocument,
        onSave: @escaping (TrafficRuleDocument) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: UnifiedTrafficRulesViewModel(document: document))
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        @Bindable var model = model
        let colors = DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)

        VStack(spacing: 0) {
            UnifiedTrafficRulesManagerHeader(
                ruleCount: model.document.rules.count,
                colors: colors,
                onAdd: addRule,
                onSave: {
                    onSave(model.preparedDocument())
                    onClose()
                },
                onClose: onClose
            )
            Divider()
            if model.document.rules.isEmpty {
                StateView(
                    kind: .empty(
                        title: "No Traffic Rules",
                        message: "Create a rule to mock, redirect, rewrite, block, delay, pause, or script matching traffic.",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ),
                    palette: colors
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(model.orderedRules) { rule in
                            UnifiedTrafficRuleRow(
                                rule: rule,
                                colors: colors,
                                canMoveUp: model.canMove(ruleID: rule.id, direction: .up),
                                canMoveDown: model.canMove(ruleID: rule.id, direction: .down),
                                onToggle: { model.setEnabled($0, ruleID: rule.id) },
                                onEdit: { editingRule = rule },
                                onMoveUp: { model.move(ruleID: rule.id, direction: .up) },
                                onMoveDown: { model.move(ruleID: rule.id, direction: .down) },
                                onDelete: { pendingDeletion = rule }
                            )
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 1_000, minHeight: 680)
        .background(colors.background)
        .sheet(item: $editingRule) { rule in
            UnifiedTrafficRuleEditor(rule: rule) { updated in
                model.upsert(updated)
            }
        }
        .confirmationDialog(
            "Delete traffic rule?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                if let rule = pendingDeletion {
                    model.delete(ruleID: rule.id)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion.map { "\($0.name) and its actions will be removed from this draft." } ?? "")
        }
    }

    private func addRule() {
        editingRule = TrafficRule(
            name: "New Rule",
            priority: model.document.rules.count,
            matcher: .init(),
            actions: [UnifiedTrafficRuleActionFormModel.defaultAction(for: .mock)]
        )
    }
}

private struct UnifiedTrafficRulesManagerHeader: View {
    let ruleCount: Int
    let colors: DesignSystem.ColorPalette
    let onAdd: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Traffic Rules")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(colors.textPrimary)
                Text("\(ruleCount) configured · lower priority runs first")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(title: "Add Rule", systemImage: "plus", style: .ghost(colors), action: onAdd)
            ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors), action: onClose)
            ControlButton(title: "Save Rules", systemImage: "checkmark", style: .filled(colors), action: onSave)
        }
        .padding(DesignSystem.Spacing.xl)
        .background(colors.surface)
    }
}
