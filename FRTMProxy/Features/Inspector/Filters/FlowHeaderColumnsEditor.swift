import SwiftUI

struct FlowHeaderColumnsEditor: View {
    @Binding var data: Data
    let colors: DesignSystem.ColorPalette
    @Environment(\.dismiss) private var dismiss
    @State private var columns: [FlowHeaderColumn] = []
    @State private var name = ""
    @State private var phase: FlowHeaderColumn.Phase = .response
    @State private var search = ""
    @State private var error: String?
    @State private var unreadable = false
    @State private var showsReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Header Columns").font(DesignSystem.Fonts.title)
            Text("Up to eight local columns. Repeated values remain separate. Configuration is saved on this Mac; captured values are not stored in preferences.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
            SearchField(text: $search, placeholder: "Find configured headers", colors: colors)
            List {
                ForEach(columns.filter { search.isEmpty || $0.title.localizedStandardContains(search) }) { column in
                    HStack {
                        Text(column.title)
                        Spacer()
                        ControlButton(title: "Move Up", systemImage: "arrow.up", style: .ghost(colors), disabled: columns.first?.id == column.id) { moveUp(column.id) }
                        ControlButton(title: "Remove", systemImage: "minus.circle", style: .ghost(colors)) { columns.removeAll { $0.id == column.id } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            HStack(spacing: DesignSystem.Spacing.sm) {
                Picker("Phase", selection: $phase) {
                    ForEach(FlowHeaderColumn.Phase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Header name, e.g. X-Request-ID", text: $name)
                ControlButton(title: "Add", systemImage: "plus", style: .ghost(colors), disabled: unreadable || columns.count >= 8) {
                    let candidate = columns + [FlowHeaderColumn(phase: phase, name: name.trimmingCharacters(in: .whitespacesAndNewlines))]
                    do { try FlowHeaderColumn.validate(candidate); columns = candidate; name = ""; error = nil }
                    catch { self.error = "Use a valid, distinct HTTP header name (128 bytes); maximum eight columns." }
                }
            }
            .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(colors.warning) }
            if unreadable { ControlButton(title: "Reset Configuration", systemImage: "arrow.counterclockwise", style: .ghost(colors)) { showsReset = true } }
            HStack {
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors), disabled: unreadable) {
                    do { try FlowHeaderColumn.validate(columns); data = try JSONEncoder().encode(columns); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .padding(DesignSystem.Spacing.lg)
        .background(colors.background)
        .frame(minWidth: DesignSystem.Metrics.scaled(560), minHeight: DesignSystem.Metrics.scaled(380))
        .alert("Reset header column configuration?", isPresented: $showsReset) {
            Button("Reset") { columns = []; unreadable = false; error = nil }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Saving will replace the unreadable column configuration. Captured traffic is preserved.") }
        .task {
            do { columns = try FlowHeaderColumn.decode(data) }
            catch { unreadable = true; self.error = "Saved column configuration could not be read; it has been preserved." }
        }
    }
    private func moveUp(_ id: UUID) {
        guard let index = columns.firstIndex(where: { $0.id == id }), index > 0 else { return }
        columns.swapAt(index, index - 1)
    }
}
