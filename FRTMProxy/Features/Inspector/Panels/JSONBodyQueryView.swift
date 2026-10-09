import SwiftUI

struct JSONBodyQueryView: View {
    let payload: String
    let isTruncated: Bool
    let colors: DesignSystem.ColorPalette
    @State private var model = JSONBodyQueryModel()
    @State private var query = ""
    @State private var mode: JSONBodyQuery.Mode = .path

    var body: some View {
        DisclosureGroup("Search JSON Preview") {
            ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Picker("Search Mode", selection: $mode) {
                    ForEach(JSONBodyQuery.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(mode == .path ? "$.items[*].id" : "Key or value", text: $query)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                    .accessibilityLabel(mode == .path ? "JSONPath expression" : "JSON key or value search")
                    .help("JSONPath supports $, .field, [index], [*], .* and [\"quoted key\"].")
                if isTruncated {
                    Label("Search covers the truncated preview only.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(colors.warning)
                }
                if model.isSearching { ProgressView("Searching…") }
                if let error = model.error { Text(error).foregroundStyle(colors.warning).lineLimit(3).help(error) }
                if !model.output.isEmpty {
                    HStack {
                        Text("\(model.count) result(s)")
                        Spacer()
                        ControlButton(title: "Copy Results", systemImage: "doc.on.doc", style: .ghost(colors)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.output, forType: .string)
                        }
                    }
                    ScrollView([.horizontal, .vertical]) {
                        Text(model.output)
                            .font(DesignSystem.Fonts.monoBody)
                            .foregroundStyle(colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(DesignSystem.Spacing.sm)
                    }
                    .frame(height: DesignSystem.Metrics.scaled(72))
                    .background(colors.surfaceElevated)
                    .clipShape(.rect(cornerRadius: DesignSystem.Radius.sm))
                    .accessibilityIdentifier("inspector.json.results")
                }
            }
            .font(DesignSystem.Fonts.caption)
            .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .frame(maxHeight: DesignSystem.Metrics.scaled(140))
        }
        .tint(colors.accent)
        .foregroundStyle(colors.textPrimary)
        .onChange(of: query) { _, _ in model.search(body: payload, query: query, mode: mode) }
        .onChange(of: mode) { _, _ in model.search(body: payload, query: query, mode: mode) }
        .onChange(of: payload) { _, _ in model.search(body: payload, query: query, mode: mode) }
        .onDisappear { model.cancel() }
    }
}
