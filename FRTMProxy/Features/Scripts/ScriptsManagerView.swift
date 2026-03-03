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
        VStack(spacing: DesignSystem.Metrics.scaled(16)) {
            header
            Divider()
            if scripts.isEmpty {
                emptyState
            } else {
                scriptsList
            }
        }
        .padding(DesignSystem.Metrics.scaled(20))
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
        HStack(spacing: DesignSystem.Metrics.scaled(12)) {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(4)) {
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
            LazyVStack(spacing: DesignSystem.Metrics.scaled(8)) {
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
            .padding(.vertical, DesignSystem.Metrics.scaled(4))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Metrics.scaled(12)) {
            Spacer()
            Image(systemName: "curlybraces")
                .font(.system(size: 36))
                .foregroundStyle(colors.textSecondary.opacity(0.5))
            Text("No script rules")
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            Text("Add a script to transform responses dynamically.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ScriptRuleRow

private struct ScriptRuleRow: View {
    @Binding var script: ScriptRule
    let colors: DesignSystem.ColorPalette
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(12)) {
            Toggle("", isOn: $script.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)

            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(3)) {
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
        .padding(DesignSystem.Metrics.scaled(12))
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(12))
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
            HStack(spacing: DesignSystem.Metrics.scaled(12)) {
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
            .padding(DesignSystem.Metrics.scaled(16))
            .background(colors.surfaceElevated)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(colors.border.opacity(0.7)), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(16)) {
                    // Name
                    formField(label: "Name") {
                        TextField("My script", text: $script.name)
                            .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                            .font(DesignSystem.Fonts.sans(13))
                    }

                    // Match
                    HStack(spacing: DesignSystem.Metrics.scaled(12)) {
                        formField(label: "Host") {
                            TextField("api.example.com", text: $script.host)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                                .font(DesignSystem.Fonts.mono(12))
                        }
                        formField(label: "Path (prefix)") {
                            TextField("/v1/users", text: $script.path)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                                .font(DesignSystem.Fonts.mono(12))
                        }
                    }

                    // Code editor
                    VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
                        Text("Script")
                            .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        CodeEditorView(text: $script.code, isEditable: true, minHeight: 300)
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                    .stroke(colors.border.opacity(0.7), lineWidth: 1)
                            )
                    }

                    // Hint
                    Text("The function `transform(flow)` receives `{ request: { url, method, headers, body }, response: { status, headers, body } }`. Return an object with `status`, `headers`, `body` to override, or `null` to pass through.")
                        .font(DesignSystem.Fonts.sans(11))
                        .foregroundStyle(colors.textSecondary)
                        .padding(DesignSystem.Metrics.scaled(10))
                        .background(colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8)))
                }
                .padding(DesignSystem.Metrics.scaled(20))
            }
        }
        .background(colors.surface)
        .frame(minWidth: 800, minHeight: 600)
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
            Text(label)
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            content()
        }
    }
}
