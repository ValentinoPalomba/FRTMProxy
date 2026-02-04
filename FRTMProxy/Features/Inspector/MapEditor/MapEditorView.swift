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
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(16)) {
            breadcrumb
            
            editorsStack
            
            Spacer(minLength: 0)
            
            actionBar
        }
        .padding(DesignSystem.Metrics.scaled(20))
        .background(colors.background)
        .overlay {
            if !isSelectionAvailable {
                VStack(spacing: DesignSystem.Metrics.scaled(8)) {
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
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(4)) {
            Text(titlePrefix.uppercased())
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text(viewModel.title.isEmpty ? "No item selected" : viewModel.title)
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
        }
    }
    
    private var editorsStack: some View {
        Group {
            if showsRequestEditor && showsResponseEditor {
                HStack(alignment: .top, spacing: DesignSystem.Metrics.scaled(16)) {
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
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(10)) {
            HStack(alignment: .center, spacing: DesignSystem.Metrics.scaled(10)) {
                HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    if let titleBadge {
                        Text(titleBadge)
                            .foregroundStyle(colors.danger)
                            .font(DesignSystem.Fonts.sans(13, weight: .bold))
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
        .padding(DesignSystem.Metrics.scaled(14))
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
                    onAdd: viewModel.addResponseHeader,
                    onRemove: viewModel.removeResponseHeader
                )
            )
        case .params:
            return AnyView(EmptyView())
        }
    }
    
    private func tabBar(tabs: [EditorTab], selection: Binding<EditorTab>) -> some View {
        HStack(spacing: DesignSystem.Metrics.scaled(6)) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = selection.wrappedValue == tab
                Button {
                    selection.wrappedValue = tab
                } label: {
                    Text(tab.rawValue)
                        .font(DesignSystem.Fonts.sans(12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                        .padding(.vertical, DesignSystem.Metrics.scaled(6))
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                .fill(isSelected ? colors.surface : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Metrics.scaled(4))
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                        .stroke(colors.border, lineWidth: 1)
                )
        )
    }
    
    private var statusField: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(8)) {
            Text("Status")
                .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField("200", text: $viewModel.responseStatusText)
                .frame(width: DesignSystem.Metrics.scaled(72))
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
        .padding(.vertical, DesignSystem.Metrics.scaled(6))
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                        .stroke(colors.border, lineWidth: 1)
                )
        )
    }
    
    private var actionBar: some View {
        HStack {
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
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
        .padding(.top, DesignSystem.Metrics.scaled(8))
    }
}

private struct KeyValueEditor: View {
    @Binding var rows: [MapEditorKeyValueRow]
    let colors: DesignSystem.ColorPalette
    let keyPlaceholder: String
    let valuePlaceholder: String
    let emptyMessage: String
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Metrics.scaled(8)) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(colors.textSecondary)
                    .font(DesignSystem.Fonts.sans(13))
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Metrics.scaled(60), alignment: .leading)
                    .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                            .fill(colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                    .stroke(colors.border, lineWidth: 1)
                            )
                    )
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Metrics.scaled(2)) {
                        ForEach($rows) { $row in
                            KeyValueRowView(
                                row: $row,
                                colors: colors,
                                keyPlaceholder: keyPlaceholder,
                                valuePlaceholder: valuePlaceholder,
                                onRemove: onRemove
                            )
                        }
                    }
                }
                .frame(minHeight: DesignSystem.Metrics.scaled(170))
            }

            HStack {
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                        .padding(.vertical, DesignSystem.Metrics.scaled(6))
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                .fill(colors.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                        .stroke(colors.border, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct KeyValueRowView: View {
    @Binding var row: MapEditorKeyValueRow
    let colors: DesignSystem.ColorPalette
    let keyPlaceholder: String
    let valuePlaceholder: String
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(8)) {
            TextField(keyPlaceholder, text: $row.key)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                .frame(width: DesignSystem.Metrics.scaled(168))

            TextField(valuePlaceholder, text: $row.value)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                .frame(maxWidth: .infinity)

            Button {
                onRemove(row.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(colors.danger)
                    .padding(DesignSystem.Metrics.scaled(6))
                    .background(
                        
                        RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(6))
                            .fill(colors.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DesignSystem.Metrics.scaled(6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colors.border.opacity(0.9))
                .frame(height: 1)
        }
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
        HStack(alignment: .center, spacing: DesignSystem.Metrics.scaled(10)) {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(4)) {
                Text("Method")
                    .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                TextField("GET", text: $method)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                    .frame(width: DesignSystem.Metrics.scaled(104))
            }

            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(4)) {
                Text("URL")
                    .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                TextField("https://example.org/path", text: $url)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
            }
        }
    }
}
