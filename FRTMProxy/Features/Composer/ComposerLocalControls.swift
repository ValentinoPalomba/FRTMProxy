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
        .sheet(isPresented: $showsVariables, onDismiss: { Task { await model.saveLocalState() } }) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Local Variables").font(DesignSystem.Fonts.title)
                Text("Use {{NAME}} in URL, headers and body. Values are substituted once, before sending, and stored encrypted on this Mac.")
                ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.sm) {
                ForEach($model.variables) { $row in
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("NAME", text: $row.key)
                        SecureField("Value", text: $row.value)
                        ControlButton(title: "Remove", systemImage: "minus.circle", style: .ghost(colors)) { model.variables.removeAll { $0.id == row.id } }
                    }
                }
                }
                }
                ControlButton(title: "Add Variable", systemImage: "plus", style: .ghost(colors)) { model.variables.append(.init(key: "", value: "")) }
                ControlButton(title: "Done", systemImage: "checkmark", style: .filled(colors)) { showsVariables = false }
                    .keyboardShortcut(.defaultAction)
            }
            .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
            .font(DesignSystem.Fonts.body)
            .foregroundStyle(colors.textPrimary)
            .padding(DesignSystem.Spacing.lg)
            .frame(width: DesignSystem.Metrics.scaled(640), height: DesignSystem.Metrics.scaled(440))
            .background(colors.background)
        }
    }
}
