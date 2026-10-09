import SwiftUI

struct FlowDiffView: View {
    let flowA: MitmFlow
    let flowB: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onClose: () -> Void
    @State private var section: DiffSection = .responseBody
    @State private var mode: FlowComparison.Mode = .structure
    @State private var result: FlowComparison.Result?
    @State private var error: String?

    var body: some View {
        let input = FlowComparison.Input(a: flowA, b: flowB, section: section, mode: mode)
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Compare flows").font(DesignSystem.Fonts.title)
                Spacer()
                ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Picker("Section", selection: $section) {
                ForEach(DiffSection.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
            }
            Picker("Comparison", selection: $mode) {
                ForEach(FlowComparison.Mode.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(section == .requestHeaders || section == .responseHeaders)
            Text("A: \(flowA.request?.url ?? flowA.id)\nB: \(flowB.request?.url ?? flowB.id)")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary).textSelection(.enabled)
                .lineLimit(4)
                .help("A: \(flowA.request?.url ?? flowA.id)\nB: \(flowB.request?.url ?? flowB.id)")
            if let error {
                StateView(kind: .failed(title: "Comparison failed", message: error, retry: nil), palette: colors)
            } else if let result {
                if let warning = result.warning {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(colors.warning).lineLimit(3).help(warning)
                }
                Text(result.rows.isEmpty ? String(localized: "No differences in the compared data", bundle: AppLocalization.bundle) : String(localized: "\(result.rows.count) changed paths / byte blocks", bundle: AppLocalization.bundle))
                Table(result.rows) {
                    TableColumn("Path / Offset") { Text($0.id).lineLimit(2).help($0.id).textSelection(.enabled) }
                    TableColumn("A") { row in
                        Text(row.a ?? "〈absent〉").foregroundStyle(row.a == nil ? colors.textSecondary : colors.danger).lineLimit(3).help(row.a ?? "〈absent〉").textSelection(.enabled)
                    }
                    TableColumn("B") { row in
                        Text(row.b ?? "〈absent〉").foregroundStyle(row.b == nil ? colors.textSecondary : colors.success).lineLimit(3).help(row.b ?? "〈absent〉").textSelection(.enabled)
                    }
                }
                .font(DesignSystem.Fonts.monoBody)
                .scrollContentBackground(.hidden)
            } else { StateView(kind: .loading(message: "Comparing…"), palette: colors) }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(colors.textPrimary)
        .background(colors.background)
        .task(id: input) {
            result = nil
            error = nil
            let worker = Task.detached { try FlowComparison.compare(input) }
            do {
                let output = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                result = output
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
