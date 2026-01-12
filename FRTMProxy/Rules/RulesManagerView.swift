import SwiftUI

struct RulesManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var viewModel: MapRuleViewModel
    @StateObject private var editorViewModel = MapEditorViewModel()

    let onUpdate: (String, String, Int, [String: String], Bool) -> Void
    let onDelete: (String) -> Void
    let onCreate: (String, String) -> MapRule?
    let onSetRuleEnabled: (String, Bool) -> Void

    @State private var editingRule: MapRule?
    @State private var showingNewRuleSheet = false
    @State private var newRuleHost: String = ""
    @State private var newRulePath: String = "/"

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            if viewModel.rules.isEmpty {
                emptyPlaceholder
            } else {
                rulesList
            }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 620)
        .background(colors.background)
        .sheet(item: $editingRule, onDismiss: { editingRule = nil }) { rule in
            RuleEditorSheet(
                rule: rule,
                editorViewModel: editorViewModel,
                colors: colors,
                onSave: { payload, updatedRule in
                    onUpdate(rule.key, payload.responseBody, payload.responseStatus, payload.responseHeaders, rule.isEnabled)
                    viewModel.update(rule: updatedRule)
                    editorViewModel.markSynced()
                },
                onClose: { editingRule = nil }
            )
        }
        .sheet(isPresented: $showingNewRuleSheet) {
            NewRuleSheet(
                host: $newRuleHost,
                path: $newRulePath,
                colors: colors,
                onCreate: createRule
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Map Local Rules")
                    .font(DesignSystem.Fonts.mono(20, weight: .semibold))
                Text("Gestisci le risposte mock salvate e abilita/disable rapidamente le regole.")
                    .font(DesignSystem.Fonts.mono(13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(
                title: "Add Rule",
                systemImage: "plus",
                style: .filled(colors)
            ) {
                showingNewRuleSheet = true
            }
            ControlButton(
                title: "Remove",
                systemImage: "trash",
                style: .destructive(colors),
                disabled: viewModel.selection == nil
            ) {
                deleteSelectedRule()
            }
            ControlButton(
                title: "Close",
                systemImage: "xmark",
                style: .ghost(colors)
            ) {
                dismiss()
            }
        }
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.rules) { rule in
                    RuleRow(
                        rule: rule,
                        colors: colors,
                        isSelected: viewModel.selection?.key == rule.key,
                        onSelect: { viewModel.select(rule) },
                        onDoubleClick: { openEditor(for: rule) },
                        onToggle: { enabled in
                            toggle(rule: rule, enabled: enabled)
                        },
                        onDelete: {
                            onDelete(rule.key)
                            viewModel.removeRule(key: rule.key)
                        }
                    )
                    .contextMenu {
                        Button("Edit") { openEditor(for: rule) }
                        Button(rule.isEnabled ? "Disable" : "Enable") {
                            toggle(rule: rule, enabled: !rule.isEnabled)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            onDelete(rule.key)
                            viewModel.removeRule(key: rule.key)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(colors.textSecondary)
            Text("Nessuna regola salvata")
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text("Crea una nuova regola o usa Map Local su un flow per popolare questa lista.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(rule: MapRule, enabled: Bool) {
        onSetRuleEnabled(rule.key, enabled)
        var updated = rule
        updated.isEnabled = enabled
        viewModel.update(rule: updated)
    }

    private func openEditor(for rule: MapRule) {
        viewModel.select(rule)
        editingRule = rule
        editorViewModel.load(rule: rule)
    }

    private func deleteSelectedRule() {
        guard let selected = viewModel.selection else { return }
        onDelete(selected.key)
        viewModel.removeRule(key: selected.key)
    }

    private func createRule() {
        guard let rule = onCreate(newRuleHost, newRulePath) else { return }
        newRuleHost = ""
        newRulePath = "/"
        showingNewRuleSheet = false
        DispatchQueue.main.async {
            viewModel.select(rule)
            editingRule = rule
            editorViewModel.load(rule: rule)
        }
    }
}

private struct RuleRow: View {
    let rule: MapRule
    let colors: DesignSystem.ColorPalette
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            statusBadge
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: { onToggle($0) })) {
                Text("Enabled")
            }
            .toggleStyle(.switch)
            .labelsHidden()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(colors.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? colors.accent.opacity(0.12) : colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? colors.accent.opacity(0.4) : colors.border.opacity(0.5), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .gesture(
            TapGesture(count: 2)
                .onEnded { onDoubleClick() }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { onSelect() }
        )
        .padding(8)

    }

    private var statusBadge: some View {
        Text("\(rule.status)")
            .font(DesignSystem.Fonts.mono(12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colors.surfaceElevated)
            )
            .overlay(
                Capsule()
                    .stroke(colors.border.opacity(0.7), lineWidth: 1)
            )
    }
}

private struct NewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var host: String
    @Binding var path: String
    let colors: DesignSystem.ColorPalette
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Map Local Rule")
                .font(DesignSystem.Fonts.sans(18, weight: .semibold))
            Text("Specifica host e path della richiesta da intercettare. Potrai modificare body e headers dopo aver creato la regola.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Host (es. api.example.com)", text: $host)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                TextField("Path (es. /v1/resource)", text: $path)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    host = ""
                    path = "/"
                    dismiss()
                }
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private struct RuleEditorSheet: View {
    let rule: MapRule
    @ObservedObject var editorViewModel: MapEditorViewModel
    let colors: DesignSystem.ColorPalette
    let onSave: (MapEditorPayload, MapRule) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            MapEditorView(
                viewModel: editorViewModel,
                colors: colors,
                allowRequestEditing: false,
                showsRequestEditor: false,
                actions: MapEditorActions(
                    saveLabel: "Save",
                    saveIcon: "square.and.arrow.down",
                    onSave: {
                        guard let payload = editorViewModel.payload(defaultStatus: rule.status) else { return }
                        let updatedRule = MapRule(
                            key: rule.key,
                            host: rule.host,
                            path: rule.path,
                            scheme: rule.scheme,
                            body: payload.responseBody,
                            status: payload.responseStatus,
                            headers: payload.responseHeaders,
                            isEnabled: rule.isEnabled
                        )
                        onSave(payload, updatedRule)
                        onClose()
                    },
                    closeLabel: "Close",
                    closeIcon: "xmark",
                    onClose: onClose
                ),
                isSelectionAvailable: true
            )
            .onAppear {
                editorViewModel.load(rule: rule)
            }
        }
        .frame(minWidth: 980, minHeight: 700)
    }
}
