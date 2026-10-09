import SwiftUI

struct ComposerLocalControls: View {
    @ObservedObject var model: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    @State private var showsVariables = false
    @State private var showsReset = false
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Menu("History", systemImage: "clock") {
                ForEach(model.history) { draft in
                    Button("\(draft.method) \(draft.url)") { model.loadDraft(draft) }
                }
                if !model.history.isEmpty {
                    Divider()
                    Button("Clear History") { Task { await model.clearHistory() } }
                }
            }
            .menuStyle(.borderlessButton)
            .font(DesignSystem.Fonts.label)
            .foregroundStyle(colors.textPrimary)
            .fixedSize()
            .disabled(model.isRestoring || model.history.isEmpty)
            ControlButton(title: "Variables", systemImage: "curlybraces", style: .ghost(colors), disabled: model.isRestoring) { showsVariables = true }
            if model.isRestoring { ProgressView().controlSize(.small) }
            if model.restoreFailed {
                ControlButton(title: "Reset Local State", systemImage: "arrow.counterclockwise", style: .ghost(colors)) { showsReset = true }
            }

        }
        .alert("Reset local composer state?", isPresented: $showsReset) {
            Button("Reset") { Task { await model.resetLocalState() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The unreadable encrypted file is kept as a backup. History and variables will start empty.")
        }
        .sheet(isPresented: $showsVariables) {
            ComposerVariablesEditor(model: model, colors: colors)
        }
    }
}

private struct ComposerVariablesEditor: View {
    @ObservedObject var model: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ComposerHeaderRow] = []
    @State private var addedRow: UUID?
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focusedRow: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Local Variables").font(DesignSystem.Fonts.title)
            Text("Use {{NAME}} in URL, headers and body. Values are substituted once and stored encrypted on this Mac.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
            HStack {
                Text("\(rows.count) / 128 variables").font(DesignSystem.Fonts.caption)
                Spacer()
                ControlButton(title: "Add Variable", systemImage: "plus", style: .ghost(colors), disabled: saving || rows.count >= 128) {
                    let row = ComposerHeaderRow(key: "", value: "")
                    rows.append(row)
                    addedRow = row.id
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach($rows) { $row in
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                TextField("NAME", text: $row.key)
                                    .accessibilityLabel("Variable name")
                                    .focused($focusedRow, equals: row.id)
                                SecureField("Value", text: $row.value)
                                    .accessibilityLabel("Variable value")
                                ControlButton(title: "Remove", systemImage: "minus.circle", style: .ghost(colors)) {
                                    rows.removeAll { $0.id == row.id }
                                }
                            }
                            .id(row.id)
                        }
                    }
                }
                .task(id: addedRow) {
                    guard let id = addedRow else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                    await Task.yield()
                    if !Task.isCancelled { focusedRow = id }
                }
            }
            .disabled(saving)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.warning)
                    .lineLimit(3)
                    .help(error)
            }
            HStack {
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors), disabled: saving) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors), disabled: saving) {
                    saving = true
                    Task {
                        do {
                            try await model.saveVariables(rows)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .padding(DesignSystem.Spacing.lg)
        .frame(width: DesignSystem.Metrics.scaled(640), height: DesignSystem.Metrics.scaled(440))
        .background(colors.background)
        .interactiveDismissDisabled(saving)
        .onAppear { rows = model.variables }
    }
}
