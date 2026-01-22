import SwiftUI

struct MapEditorActions {
    let saveLabel: String
    let saveIcon: String
    let onSave: (() -> Void)?
    let closeLabel: String
    let closeIcon: String
    let onClose: (() -> Void)?

    init(
        saveLabel: String = "Save",
        saveIcon: String = "square.and.arrow.down",
        onSave: (() -> Void)? = nil,
        closeLabel: String = "Close",
        closeIcon: String = "xmark",
        onClose: (() -> Void)? = nil
    ) {
        self.saveLabel = saveLabel
        self.saveIcon = saveIcon
        self.onSave = onSave
        self.closeLabel = closeLabel
        self.closeIcon = closeIcon
        self.onClose = onClose
    }
}

struct MapEditorView: View {
    @ObservedObject var viewModel: MapEditorViewModel
    let colors: DesignSystem.ColorPalette
    var allowRequestEditing: Bool = true
    var showsRequestEditor: Bool = true
    var showsResponseEditor: Bool = true
    var actions: MapEditorActions
    var isSelectionAvailable: Bool = true
    var titlePrefix: String = "Map Local"
    
    @State private var requestTab: EditorTab = .body
    @State private var responseTab: EditorTab = .body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            breadcrumb
            
            editorsStack
            
            Spacer(minLength: 0)
            
            actionBar
        }
        .padding(20)
        .background(colors.background)
        .overlay {
            if !isSelectionAvailable {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 30))
                        .foregroundStyle(colors.textSecondary)
                    Text("Seleziona un flow o una regola per \(titlePrefix)")
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
    
    private var breadcrumb: some View {
        HStack(spacing: 8) {
            Text(titlePrefix)
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text("/")
                .foregroundStyle(colors.textSecondary)
            Text(viewModel.title.isEmpty ? "Nessun elemento selezionato" : viewModel.title)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
    }
    
    private var editorsStack: some View {
        Group {
            if showsRequestEditor && showsResponseEditor {
                HStack(alignment: .top, spacing: 16) {
                    requestEditorCard
                    responseEditorCard
                }
            } else if showsRequestEditor {
                requestEditorCard
            } else if showsResponseEditor {
                responseEditorCard
            }
        }
    }
    
    private var requestEditorCard: some View {
        editorCard(
            title: "Request",
            titleBadge: "*",
            tabs: [.body, .headers, .params],
            selectedTab: $requestTab,
            allowEditing: allowRequestEditing && isSelectionAvailable,
            bodyContent: requestTabContent,
            topAccessory: AnyView(
                RequestMetaEditor(
                    method: $viewModel.requestMethod,
                    url: $viewModel.requestUrl,
                    colors: colors
                )
            )
        )
    }

    private var responseEditorCard: some View {
        editorCard(
            title: "Response",
            tabs: [.body, .headers],
            selectedTab: $responseTab,
            allowEditing: isSelectionAvailable,
            bodyContent: responseTabContent,
            topAccessory: AnyView(statusField)
        )
        .frame(maxWidth: .infinity)
    }

    private func editorCard(
        title: String,
        titleBadge: String? = nil,
        tabs: [EditorTab],
        selectedTab: Binding<EditorTab>,
        allowEditing: Bool,
        bodyContent: @escaping (EditorTab) -> AnyView,
        trailingHeader: AnyView? = nil,
        topAccessory: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(17, weight: .semibold))
                    if let titleBadge {
                        Text(titleBadge)
                            .foregroundStyle(colors.danger)
                            .font(.headline)
                    }
                }
                Spacer()
                trailingHeader
            }

            if let topAccessory {
                topAccessory
            }
            
            tabBar(tabs: tabs, selection: selectedTab)
            
            bodyContent(selectedTab.wrappedValue)
        }
        .padding(16)
        .surfaceCard(fill: colors.surface, stroke: colors.border, shadowOpacity: 0.08)
        .disabled(!allowEditing)
        .opacity(!allowEditing ? 0.6 : 1)
    }
    
    private func requestTabContent(_ tab: EditorTab) -> AnyView {
        switch tab {
        case .body:
            return AnyView(CodeEditorView(text: $viewModel.requestBody, isEditable: allowRequestEditing && isSelectionAvailable))
        case .headers:
            return AnyView(
                KeyValueEditor(
                    rows: $viewModel.requestHeaders,
                    colors: colors,
                    keyPlaceholder: "Header",
                    valuePlaceholder: "Value",
                    emptyMessage: "Nessun header della request",
                    useMultilineValue: true,
                    onAdd: viewModel.addRequestHeader,
                    onRemove: viewModel.removeRequestHeader
                )
            )
        case .params:
            return AnyView(
                KeyValueEditor(
                    rows: $viewModel.queryParameters,
                    colors: colors,
                    keyPlaceholder: "Parametro",
                    valuePlaceholder: "Valore",
                    emptyMessage: "Nessun parametro query",
                    useMultilineValue: false,
                    onAdd: viewModel.addQueryParameter,
                    onRemove: viewModel.removeQueryParameter
                )
            )
        }
    }
    
    private func responseTabContent(_ tab: EditorTab) -> AnyView {
        switch tab {
        case .body:
            return AnyView(CodeEditorView(text: $viewModel.responseBody, isEditable: isSelectionAvailable))
        case .headers:
            return AnyView(
                KeyValueEditor(
                    rows: $viewModel.responseHeaders,
                    colors: colors,
                    keyPlaceholder: "Header",
                    valuePlaceholder: "Value",
                    emptyMessage: "Nessun header della response",
                    useMultilineValue: true,
                    onAdd: viewModel.addResponseHeader,
                    onRemove: viewModel.removeResponseHeader
                )
            )
        case .params:
            return AnyView(EmptyView())
        }
    }
    
    private func tabBar(tabs: [EditorTab], selection: Binding<EditorTab>) -> some View {
        HStack(spacing: 16) {
            ForEach(tabs, id: \.self) { tab in
                VStack(spacing: 6) {
                    Button {
                        selection.wrappedValue = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(DesignSystem.Fonts.sans(13, weight: selection.wrappedValue == tab ? .semibold : .medium))
                            .foregroundStyle(selection.wrappedValue == tab ? colors.textPrimary : colors.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    
                    Rectangle()
                        .fill(selection.wrappedValue == tab ? colors.accent : .clear)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.bottom, 6)
    }
    
    private var statusField: some View {
        HStack(spacing: 8) {
            Text("Status")
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField("200", text: $viewModel.responseStatusText)
                .frame(width: 72)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        }
    }
    
    private var actionBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isModified ? colors.warning : colors.textSecondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(viewModel.isModified ? "Modified" : "Synced")
                    .font(DesignSystem.Fonts.sans(12, weight: .medium))
                    .foregroundStyle(viewModel.isModified ? colors.textPrimary : colors.textSecondary)
            }
            
            Spacer()
            
            if let onSave = actions.onSave {
                ControlButton(title: actions.saveLabel, systemImage: actions.saveIcon, style: .ghost(colors), disabled: !isSelectionAvailable) {
                    onSave()
                }
            }
            
            if let onClose = actions.onClose {
                ControlButton(title: actions.closeLabel, systemImage: actions.closeIcon, style: .ghost(colors)) {
                    onClose()
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct KeyValueEditor: View {
    @Binding var rows: [MapEditorKeyValueRow]
    let colors: DesignSystem.ColorPalette
    let keyPlaceholder: String
    let valuePlaceholder: String
    let emptyMessage: String
    let useMultilineValue: Bool
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(colors.textSecondary)
                    .font(DesignSystem.Fonts.sans(13))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach($rows) { $row in
                            KeyValueRowView(
                                row: $row,
                                colors: colors,
                                keyPlaceholder: keyPlaceholder,
                                valuePlaceholder: valuePlaceholder,
                                useMultilineValue: useMultilineValue,
                                onRemove: onRemove
                            )
                        }
                    }
                }
                .frame(minHeight: 180)
            }

            HStack {
                Spacer()
                Button(action: onAdd) {
                    Label("Aggiungi", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

private struct KeyValueRowView: View {
    @Binding var row: MapEditorKeyValueRow
    let colors: DesignSystem.ColorPalette
    let keyPlaceholder: String
    let valuePlaceholder: String
    let useMultilineValue: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(alignment: useMultilineValue ? .top : .center, spacing: 10) {
            TextField(keyPlaceholder, text: $row.key)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                .frame(width: 180)

            if useMultilineValue {
                ZStack(alignment: .topLeading) {
                    if row.value.isEmpty {
                        Text(valuePlaceholder)
                            .foregroundStyle(colors.textSecondary.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $row.value)
                        .font(DesignSystem.Fonts.mono(12))
                        .frame(minHeight: 48, maxHeight: 140)
                        .padding(4)
                        .background(Color.clear)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colors.border, lineWidth: 1)
                        )
                )
            } else {
                TextField(valuePlaceholder, text: $row.value)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
            }

            Button {
                onRemove(row.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(colors.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colors.border, lineWidth: 1)
                )
        )
    }
}

private enum EditorTab: String {
    case body = "Body"
    case headers = "Headers"
    case params = "Params"
}

private struct RequestMetaEditor: View {
    @Binding var method: String
    @Binding var url: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Method")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    TextField("GET", text: $method)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                        .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    TextField("https://example.org/path", text: $url)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                }
            }
        }
    }
}
