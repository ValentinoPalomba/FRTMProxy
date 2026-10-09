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
                    .keyboardShortcut(.cancelAction)
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
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DesignSystem.Spacing.xl)
            .background(colors.surface)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    UnifiedTrafficRuleGeneralEditor(draft: draft, colors: colors)
                    Divider()
                    UnifiedTrafficRuleMatcherEditor(draft: draft, colors: colors)
                    Divider()
                    UnifiedTrafficRuleActionsEditor(draft: draft, colors: colors)
                    if !draft.validationErrors.isEmpty {
                        Label(validationSummary, systemImage: "exclamationmark.triangle")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(colors.danger)
                            .lineLimit(3)
                            .help(validationSummary)
                            .accessibilityLabel("Validation errors: \(validationSummary)")
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
        }
        .frame(minWidth: DesignSystem.Metrics.scaled(820), minHeight: DesignSystem.Metrics.scaled(620))
        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .tint(colors.accent)
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
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Label("General", systemImage: "slider.horizontal.3")
                .font(DesignSystem.Fonts.title)
            HStack(spacing: DesignSystem.Spacing.lg) {
                TextField("Rule name", text: $draft.rule.name)
                    .accessibilityLabel("Rule name")
                Toggle("Enabled", isOn: $draft.rule.isEnabled)
            }
            Text("Rules execute from top to bottom. Reorder them in the Traffic Rules list.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
    }
}
