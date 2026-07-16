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
    @State private var pendingDeletion: MapRule?

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            Divider()
            if viewModel.rules.isEmpty {
                emptyPlaceholder
            } else {
                rulesList
            }
        }
        .padding(DesignSystem.Spacing.lg)
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
        .confirmationDialog(
            "Delete Map Local rule?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                guard let rule = pendingDeletion else { return }
                delete(rule)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion.map { "\($0.host)\($0.path) will be removed." } ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Map Local Rules")
                    .font(DesignSystem.Fonts.mono(20, weight: .semibold))
                Text("Manage saved mock responses and quickly enable/disable rules.")
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
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
                            pendingDeletion = rule
                        }
                    )
                    .contextMenu {
                        Button("Edit") { openEditor(for: rule) }
                        Button(rule.isEnabled ? "Disable" : "Enable") {
                            toggle(rule: rule, enabled: !rule.isEnabled)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            pendingDeletion = rule
                        }
                    }
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var emptyPlaceholder: some View {
        StateView(
            kind: .empty(
                title: "No rules saved",
                message: "Create a new rule or use Map Local on a flow to populate this list.",
                systemImage: "folder.badge.questionmark"
            ),
            palette: colors
        )
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
        pendingDeletion = selected
    }

    private func delete(_ rule: MapRule) {
        onDelete(rule.key)
        viewModel.removeRule(key: rule.key)
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
        HStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
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
            .accessibilityLabel("Delete rule")
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(isSelected ? colors.accent.opacity(0.12) : colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(isSelected ? colors.accent.opacity(0.4) : colors.border.opacity(0.5), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .gesture(
            TapGesture(count: 2)
                .onEnded { onDoubleClick() }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { onSelect() }
        )
        .padding(DesignSystem.Spacing.sm)

    }

    private var statusBadge: some View {
        Text("\(rule.status)")
            .font(DesignSystem.Fonts.mono(12, weight: .semibold))
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(
                Capsule()
                    .fill(colors.surfaceElevated)
            )
            .overlay(
                Capsule()
                    .stroke(colors.border.opacity(0.7), lineWidth: 1)
            )
            .accessibilityLabel("Status \(rule.status)")
    }
}

private struct NewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var host: String
    @Binding var path: String
    let colors: DesignSystem.ColorPalette
    let onCreate: () -> Void
    @State private var isApplyingURLSplit = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("New Map Local Rule")
                .font(DesignSystem.Fonts.sans(18, weight: .semibold))
            Text("Specify the host and path of the request to intercept. You can edit body and headers after creating the rule.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                TextField("Host (e.g. api.example.com)", text: $host)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "network"))
                    .onChange(of: host) { oldValue, newValue in
                        applyURLSplitIfNeeded(changedField: .host, previousValue: oldValue, newValue: newValue)
                    }
                TextField("Path (e.g. /v1/resource)", text: $path)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "arrow.turn.down.right"))
                    .onChange(of: path) { oldValue, newValue in
                        applyURLSplitIfNeeded(changedField: .path, previousValue: oldValue, newValue: newValue)
                    }
                Text("Wildcard support: use * or ? in host/path (e.g. *.example.com, /v1/*).")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
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
        .padding(DesignSystem.Spacing.xl)
        .frame(minWidth: 420)
    }

    private func applyURLSplitIfNeeded(changedField: HostPathInputField, previousValue: String, newValue: String) {
        guard !isApplyingURLSplit else { return }
        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        let hostWasEmpty: Bool
        let pathWasEmpty: Bool
        switch changedField {
        case .host:
            hostWasEmpty = previousValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            pathWasEmpty = currentPath.isEmpty || currentPath == "/"
        case .path:
            hostWasEmpty = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let previousPath = previousValue.trimmingCharacters(in: .whitespacesAndNewlines)
            pathWasEmpty = previousPath.isEmpty || previousPath == "/"
        }

        guard hostWasEmpty && pathWasEmpty else { return }
        guard let split = FormattingUtils.splitHostAndPath(from: trimmedValue) else { return }

        isApplyingURLSplit = true
        host = split.host
        path = split.path
        isApplyingURLSplit = false
    }
}

private enum HostPathInputField {
    case host
    case path
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
