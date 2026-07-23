import SwiftUI

struct UnifiedTrafficRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    @State private var draft: UnifiedTrafficRuleDraft
    let onSave: (TrafficRule) -> Void

    init(rule: TrafficRule, onSave: @escaping (TrafficRule) -> Void) {
        _draft = State(initialValue: UnifiedTrafficRuleDraft(rule: rule))
        self.onSave = onSave
    }

    var body: some View {
        @Bindable var draft = draft
        let colors = DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)

        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Traffic Rule")
                        .font(DesignSystem.Fonts.title)
                        .foregroundStyle(colors.textPrimary)
                    Text("Match traffic, then apply ordered actions.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { dismiss() }
                ControlButton(
                    title: "Save Rule",
                    systemImage: "checkmark",
                    style: .filled(colors),
                    disabled: !canSave
                ) {
                        onSave(draft.materializedRule())
                        dismiss()
                    }
                    .accessibilityHint(canSave ? "Saves the traffic rule" : validationSummary)
            }
            .padding(DesignSystem.Spacing.xl)
            .background(colors.surface)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    UnifiedTrafficRuleGeneralEditor(draft: draft)
                    Divider()
                    UnifiedTrafficRuleMatcherEditor(draft: draft)
                    Divider()
                    UnifiedTrafficRuleActionsEditor(draft: draft)
                    if !draft.validationErrors.isEmpty {
                        Label(validationSummary, systemImage: "exclamationmark.triangle")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(colors.danger)
                            .accessibilityLabel("Validation errors: \(validationSummary)")
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(colors.background)
    }

    private var canSave: Bool {
        !draft.rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.rule.actions.isEmpty
            && draft.validationErrors.isEmpty
    }

    private var validationSummary: String {
        if draft.rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A rule name is required."
        }
        if draft.rule.actions.isEmpty {
            return "Add at least one action."
        }
        return draft.validationErrors.joined(separator: ", ")
    }
}

private struct UnifiedTrafficRuleGeneralEditor: View {
    @Bindable var draft: UnifiedTrafficRuleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Label("General", systemImage: "slider.horizontal.3")
                .font(.headline)
            HStack(spacing: DesignSystem.Spacing.lg) {
                TextField("Rule name", text: $draft.rule.name)
                    .accessibilityLabel("Rule name")
                Toggle("Enabled", isOn: $draft.rule.isEnabled)
            }
            Text("Rules execute from top to bottom. Reorder them in the Traffic Rules list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
