import SwiftUI

struct AlertRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let colors: DesignSystem.ColorPalette
    private let id: UUID
    private let createdAt: Date
    private let onSave: (AlertRule) -> Void
    private let onCancel: () -> Void

    @State private var name: String
    @State private var query: String
    @State private var isEnabled: Bool

    init(
        rule: AlertRule,
        colors: DesignSystem.ColorPalette,
        onSave: @escaping (AlertRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.colors = colors
        self.id = rule.id
        self.createdAt = rule.createdAt
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: rule.name)
        _query = State(initialValue: rule.query)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Edit Alert Rule")
                .font(DesignSystem.Fonts.titleLarge)
                .foregroundStyle(colors.textPrimary)

            SettingsCard(title: "Rule", colors: colors) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    TextField("Name", text: $name)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "tag"))
                    TextField("Query", text: $query)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "magnifyingglass"))
                    Toggle(isOn: $isEnabled) {
                        Text("Enabled")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                        .toggleStyle(SwitchToggleStyle())
                    Text("Examples: `status:>=400`, `host:api.example.com method:POST`, `type:json -status:2xx`.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                ControlButton(
                    title: "Save",
                    systemImage: "checkmark",
                    style: .filled(colors),
                    disabled: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    let updated = AlertRule(
                        id: id,
                        name: name,
                        query: query,
                        isEnabled: isEnabled,
                        createdAt: createdAt
                    )
                    onSave(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(minWidth: 560, minHeight: 380)
        .background(colors.background)
    }
}
