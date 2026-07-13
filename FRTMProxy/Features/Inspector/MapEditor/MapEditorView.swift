import SwiftUI

struct MapEditorActions {
    let saveLabel: LocalizedStringKey
    let saveIcon: String
    let onSave: (() -> Void)?
    let closeLabel: LocalizedStringKey
    let closeIcon: String
    let onClose: (() -> Void)?

    init(
        saveLabel: LocalizedStringKey = "Save",
        saveIcon: String = "square.and.arrow.down",
        onSave: (() -> Void)? = nil,
        closeLabel: LocalizedStringKey = "Close",
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            breadcrumb
            
            editorsStack
            
            Spacer(minLength: 0)
            
            actionBar
        }
        .padding(DesignSystem.Spacing.lg)
        .background(colors.background)
        .overlay {
            if !isSelectionAvailable {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: DesignSystem.Metrics.scaled(30)))
                        .foregroundStyle(colors.textSecondary)
                    Text("Select a flow or rule for \(titlePrefix)")
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
    
    private var breadcrumb: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(titlePrefix)
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text("/")
                .foregroundStyle(colors.textSecondary)
            Text(viewModel.title.isEmpty ? "No item selected" : viewModel.title)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
    }
    
    private var editorsStack: some View {
        Group {
            if showsRequestEditor && showsResponseEditor {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                HStack(spacing: DesignSystem.Spacing.xs) {
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
        .padding(DesignSystem.Spacing.lg)
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
                    emptyMessage: "No request headers",
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
                    keyPlaceholder: "Parameter",
                    valuePlaceholder: "Value",
                    emptyMessage: "No query parameters",
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
                    emptyMessage: "No response headers",
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
        HStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(tabs, id: \.self) { tab in
                VStack(spacing: DesignSystem.Spacing.sm) {
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
                        .frame(height: DesignSystem.Metrics.scaled(2))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.bottom, DesignSystem.Spacing.sm)
    }
    
    private var statusField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text("Status")
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField("200", text: $viewModel.responseStatusText)
                .frame(width: DesignSystem.Metrics.scaled(72))
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        }
    }
    
    private var actionBar: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Circle()
                    .fill(viewModel.isModified ? colors.warning : colors.textSecondary.opacity(0.4))
                    .frame(width: DesignSystem.Metrics.scaled(10), height: DesignSystem.Metrics.scaled(10))
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
        .padding(.top, DesignSystem.Spacing.sm)
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
        VStack(spacing: DesignSystem.Spacing.sm) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(colors.textSecondary)
                    .font(DesignSystem.Fonts.sans(13))
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Metrics.scaled(60), alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
                .frame(minHeight: DesignSystem.Metrics.scaled(180))
            }

            HStack {
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.top, DesignSystem.Spacing.xs)
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
        HStack(alignment: useMultilineValue ? .top : .center, spacing: DesignSystem.Spacing.sm) {
            TextField(keyPlaceholder, text: $row.key)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                .frame(width: DesignSystem.Metrics.scaled(180))

            if useMultilineValue {
                ZStack(alignment: .topLeading) {
                    if row.value.isEmpty {
                        Text(valuePlaceholder)
                            .foregroundStyle(colors.textSecondary.opacity(0.7))
                    }
                    TextEditor(text: $row.value)
                        .frame(minHeight: DesignSystem.Metrics.scaled(48), maxHeight: DesignSystem.Metrics.scaled(140))
                }
                .frame(maxWidth: .infinity)
                .proxyTextEditor(palette: colors)
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
            .accessibilityLabel("Remove")
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Method")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    TextField("GET", text: $method)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                        .frame(width: DesignSystem.Metrics.scaled(120))
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
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
