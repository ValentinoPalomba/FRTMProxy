import SwiftUI

// MARK: - ScriptsManagerView

struct ScriptsManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore

    @Binding var scripts: [ScriptRule]
    let onSave: ([ScriptRule]) -> Void
    let onClose: () -> Void

    @State private var editingScript: ScriptRule?
    @State private var showNewScriptSheet = false

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            Divider()
            if scripts.isEmpty {
                emptyState
            } else {
                scriptsList
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 780, minHeight: 500)
        .background(colors.background)
        .sheet(item: $editingScript) { script in
            ScriptEditorSheet(
                script: script,
                colors: colors,
                onSave: { updated in
                    if let idx = scripts.firstIndex(where: { $0.id == updated.id }) {
                        scripts[idx] = updated
                    }
                    onSave(scripts)
                    editingScript = nil
                },
                onClose: { editingScript = nil }
            )
        }
        .sheet(isPresented: $showNewScriptSheet) {
            ScriptEditorSheet(
                script: ScriptRule(),
                colors: colors,
                onSave: { newScript in
                    scripts.append(newScript)
                    onSave(scripts)
                    showNewScriptSheet = false
                },
                onClose: { showNewScriptSheet = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Script Rules")
                    .font(DesignSystem.Fonts.sans(20, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Transform responses dynamically using JavaScript.")
                    .font(DesignSystem.Fonts.sans(13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(title: "Add Script", systemImage: "plus", style: .filled(colors)) {
                showNewScriptSheet = true
            }
            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) {
                onClose()
            }
        }
    }

    // MARK: - List

    private var scriptsList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                ForEach($scripts) { $script in
                    ScriptRuleRow(
                        script: $script,
                        colors: colors,
                        onEdit: { editingScript = script },
                        onDelete: {
                            scripts.removeAll { $0.id == script.id }
                            onSave(scripts)
                        }
                    )
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        StateView(
            kind: .empty(
                title: "No script rules",
                message: "Add a script to transform responses dynamically.",
                systemImage: "curlybraces"
            ),
            palette: colors
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ScriptRuleRow

private struct ScriptRuleRow: View {
    @Binding var script: ScriptRule
    let colors: DesignSystem.ColorPalette
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Toggle("", isOn: $script.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(script.name.isEmpty ? "(Untitled)" : script.name)
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(scriptSummary)
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ControlButton(title: "Edit", systemImage: "pencil", style: .ghost(colors)) { onEdit() }
            ControlButton(title: "Delete", systemImage: "trash", style: .destructive(colors)) { onDelete() }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var scriptSummary: String {
        let host = script.host.isEmpty ? "*" : script.host
        let path = script.path.isEmpty ? "/*" : script.path
        return "\(host)\(path)"
    }
}

// MARK: - ScriptEditorSheet

private struct ScriptEditorSheet: View {
    @State private var script: ScriptRule
    let colors: DesignSystem.ColorPalette
    let onSave: (ScriptRule) -> Void
    let onClose: () -> Void

    init(script: ScriptRule, colors: DesignSystem.ColorPalette, onSave: @escaping (ScriptRule) -> Void, onClose: @escaping () -> Void) {
        _script = State(initialValue: script)
        self.colors = colors
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "curlybraces")
                    .font(.system(size: DesignSystem.Metrics.scaled(16), weight: .semibold))
                    .foregroundStyle(colors.accent)
                Text(script.name.isEmpty ? "New Script" : script.name)
                    .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { onClose() }
                ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors)) { onSave(script) }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(colors.surfaceElevated)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(colors.border.opacity(0.7)), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    // Name
                    formField(label: "Name") {
                        TextField("My script", text: $script.name)
                            .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "textformat"))
                            .font(DesignSystem.Fonts.sans(13))
                    }

                    // Match
                    HStack(spacing: DesignSystem.Spacing.md) {
                        formField(label: "Host") {
                            TextField("api.example.com", text: $script.host)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "network"))
                                .font(DesignSystem.Fonts.mono(12))
                        }
                        formField(label: "Path (prefix)") {
                            TextField("/v1/users", text: $script.path)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "arrow.turn.down.right"))
                                .font(DesignSystem.Fonts.mono(12))
                        }
                    }

                    // Code editor
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Script")
                            .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        CodeEditorView(text: $script.code, isEditable: true, minHeight: 300)
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                                    .stroke(colors.border.opacity(0.7), lineWidth: 1)
                            )
                    }

                    // Hint
                    Text("The function `transform(flow)` receives `{ request: { url, method, headers, body }, response: { status, headers, body } }`. Return an object with `status`, `headers`, `body` to override, or `null` to pass through.")
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                        .padding(DesignSystem.Spacing.sm)
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .background(colors.surface)
        .frame(minWidth: 800, minHeight: 600)
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            content()
        }
    }
}
