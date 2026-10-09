import SwiftUI

// MARK: - RequestComposerView

struct RequestComposerView: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    let proxyPort: Int?
    let onClose: () -> Void

    /// Controls the active panel in narrow (single-column) mode.
    @State private var narrowTab: ComposerMainTab = .request

    var body: some View {
        VStack(spacing: 0) {
            composerHeader
            Divider().overlay(colors.border.opacity(0.7))
            GeometryReader { geo in
                if geo.size.width >= DesignSystem.Metrics.scaled(900) {
                    twoColumnLayout
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    singleColumnLayout
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .clipped()
            composerFooter
        }
        .background(colors.surface)
        .tint(colors.accent)
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Two-column layout (wide)

    private var twoColumnLayout: some View {
        HStack(spacing: 0) {
            requestCard
                .frame(maxWidth: .infinity)
            Divider().overlay(colors.border.opacity(0.7))
            responseCard
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Single-column layout (narrow)

    private var singleColumnLayout: some View {
        VStack(spacing: 0) {

            // Tab switcher
            HStack(spacing: DesignSystem.Spacing.sm) {
                ComposerTabPill(label: "Request", isSelected: narrowTab == .request, colors: colors) {
                    narrowTab = .request
                }
                ComposerTabPill(label: "Response", isSelected: narrowTab == .response, colors: colors) {
                    narrowTab = .response
                }
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(colors.surfaceElevated)
            .overlay(alignment: .bottom) {
                Rectangle().fill(colors.border.opacity(0.5)).frame(height: 1)
            }

            Group {
                if narrowTab == .request {
                    requestCard
                } else {
                    responseCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
    }

    // MARK: - Header

    private var composerHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text("Compose Request")
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize()
                Spacer()
                ComposerLocalControls(model: viewModel, colors: colors)
                    .fixedSize()
                ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { onClose() }
                    .fixedSize()
                    .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Compose Request").font(DesignSystem.Fonts.heading).foregroundStyle(colors.textPrimary)
                    Spacer()
                    ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { onClose() }
                        .keyboardShortcut(.cancelAction)
                }
                ComposerLocalControls(model: viewModel, colors: colors)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(colors.surfaceElevated)
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            methodPicker
            TextField("https://example.com/api/endpoint", text: $viewModel.urlString)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                .font(DesignSystem.Fonts.mono(12))
                .onSubmit { sendRequest() }
        }
    }

    private var methodPicker: some View {
        ScrollView(.horizontal) {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(RequestComposerViewModel.httpMethods, id: \.self) { method in
                let isSelected = viewModel.method == method
                let tint = DesignSystem.Colors.methodColor(method, palette: colors)
                Button { viewModel.method = method } label: {
                    Text(method)
                        .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                                .fill(isSelected ? tint.opacity(0.12) : colors.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                                .stroke(isSelected ? tint.opacity(0.5) : colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.pressable)
                .hoverHighlight(colors)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer()
        }
        }
        .scrollIndicators(.hidden)
        .frame(height: DesignSystem.Metrics.scaled(32))
    }

    // MARK: - Request Card

    private var requestCard: some View {
        ComposerCard(title: "Request", colors: colors) {
            VStack(spacing: DesignSystem.Spacing.md) {
                urlBar
                ComposerRequestBody(viewModel: viewModel, colors: colors)
            }
        }
    }

    // MARK: - Response Card

    private var responseCard: some View {
        ComposerCard(title: "Response", colors: colors) {
            if viewModel.responseTruncated {
                Label("Preview truncated at 2 MiB — \(viewModel.responseByteCount) bytes received", systemImage: "exclamationmark.triangle")
                    .font(DesignSystem.Fonts.caption)
                    .lineLimit(2)
                    .foregroundStyle(colors.warning)
            }
            Group {
                if viewModel.isLoading {
                    StateView(kind: .loading(message: "Sending request..."), palette: colors)
                } else if let error = viewModel.errorMessage {
                    StateView(
                        kind: .failed(title: "Request failed", message: error, retry: nil),
                        palette: colors
                    )
                } else if viewModel.responseStatus != nil {
                    ComposerResponseBody(viewModel: viewModel, colors: colors)
                } else {
                    StateView(
                        kind: .empty(
                            title: "No response yet",
                            message: "Send a request to see the response",
                            systemImage: "arrow.up.circle"
                        ),
                        palette: colors
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var composerFooter: some View {
        HStack {
            if let error = viewModel.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.warning)
                    .lineLimit(2)
                    .help(error)
            }
            Spacer()
            if viewModel.isLoading {
                ControlButton(title: "Cancel", systemImage: "stop.circle", style: .ghost(colors)) { viewModel.cancel() }
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, DesignSystem.Spacing.xs)
            }
            ControlButton(
                title: "Send",
                systemImage: "paperplane.fill",
                style: .filled(colors),
                disabled: viewModel.isLoading || viewModel.isRestoring || viewModel.urlString.isEmpty
            ) {
                sendRequest()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            Rectangle()
                .fill(colors.surface.opacity(0.97))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(colors.border.opacity(0.9))
                        .frame(height: 1)
                }
        )
    }

    private func sendRequest() {
        Task { @MainActor in
            await viewModel.send(proxyPort: proxyPort)
        }
    }
}

// MARK: - ComposerCard

private struct ComposerCard<Content: View>: View {
    let title: String
    let colors: DesignSystem.ColorPalette
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(LocalizedStringKey(title))
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)
        }
        .background(colors.surface)
    }
}

// MARK: - ComposerTabPill (shared)

struct ComposerTabPill: View {
    let label: String
    let isSelected: Bool
    let colors: DesignSystem.ColorPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DesignSystem.Fonts.sans(12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .fill(isSelected ? colors.surfaceElevated : colors.surface.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .stroke(isSelected ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
        .hoverHighlight(colors)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - ComposerRequestBody

private struct ComposerRequestBody: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ComposerTabPill(label: "Body", isSelected: !viewModel.showsRequestHeaders, colors: colors) { viewModel.showsRequestHeaders = false }
                ComposerTabPill(label: "Headers", isSelected: viewModel.showsRequestHeaders, colors: colors) { viewModel.showsRequestHeaders = true }
                    .accessibilityIdentifier("composer.request.headers")
                Spacer()
            }

            Divider().overlay(colors.border.opacity(0.5))

            if !viewModel.showsRequestHeaders {
                Toggle("Body is Base64 (send decoded bytes)", isOn: $viewModel.bodyIsBase64)
                    .toggleStyle(.checkbox)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                TextEditor(text: $viewModel.requestBody)
                    .proxyTextEditor(palette: colors)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                ComposerHeadersEditor(viewModel: viewModel, colors: colors)
            }
        }
    }
}

// MARK: - ComposerHeadersEditor

private struct ComposerHeadersEditor: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette

    @FocusState private var focusedHeader: UUID?
    @State private var addedHeader: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("\(viewModel.requestHeaders.count) / 128 headers")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                ControlButton(title: "Add Header", systemImage: "plus", style: .ghost(colors), disabled: viewModel.requestHeaders.count >= 128) {
                    addedHeader = viewModel.addHeaderRow()
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach($viewModel.requestHeaders) { $row in
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                TextField("Key", text: $row.key)
                                    .accessibilityLabel("Request header name")
                                    .focused($focusedHeader, equals: row.id)
                                    .frame(maxWidth: .infinity)
                                TextField("Value", text: $row.value)
                                    .accessibilityLabel("Request header value")
                                    .frame(maxWidth: .infinity)
                                ControlButton(title: "Remove", systemImage: "minus.circle", style: .ghost(colors)) {
                                    viewModel.requestHeaders.removeAll { $0.id == row.id }
                                }
                            }
                            .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                            .id(row.id)
                        }
                    }
                }
                .task(id: addedHeader) {
                    guard let id = addedHeader else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                    await Task.yield()
                    guard !Task.isCancelled, viewModel.requestHeaders.contains(where: { $0.id == id }) else { return }
                    focusedHeader = id
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - ComposerResponseBody

private struct ComposerResponseBody: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    @State private var tab: ComposerResponseTab = .body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let status = viewModel.responseStatus {
                    ComposerStatusBadge(status: status, colors: colors)
                }
                Spacer()
                ComposerTabPill(label: "Body", isSelected: tab == .body, colors: colors) { tab = .body }
                ComposerTabPill(label: "Headers", isSelected: tab == .headers, colors: colors) { tab = .headers }
            }

            Divider().overlay(colors.border.opacity(0.5))

            switch tab {
            case .body:
                ScrollView([.vertical, .horizontal]) {
                    Text(prettyBody)
                        .accessibilityIdentifier("composer.response.body")
                        .accessibilityValue(prettyBody)
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .headers:
                if viewModel.responseHeaderFields.isEmpty {
                    Text("No headers")
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            ForEach(
                                Array(viewModel.responseHeaderFields.enumerated()),
                                id: \.offset
                            ) { _, field in
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                                    Text(field.name)
                                        .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                                        .foregroundStyle(colors.textSecondary)
                                    Text(field.value)
                                        .font(DesignSystem.Fonts.mono(12))
                                        .foregroundStyle(colors.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .padding(DesignSystem.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                                        .fill(colors.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                                                .stroke(colors.border, lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var prettyBody: String {
        guard let body = viewModel.responseBody, !body.isEmpty else { return "" }
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let prettyStr = String(data: pretty, encoding: .utf8)
        else { return body }
        return prettyStr
    }
}

// MARK: - ComposerStatusBadge

private struct ComposerStatusBadge: View {
    let status: Int
    let colors: DesignSystem.ColorPalette

    private var tint: Color {
        switch status {
        case 200..<300: return colors.success
        case 300..<400: return colors.warning
        case 400..<600: return colors.danger
        default: return colors.textSecondary
        }
    }

    var body: some View {
        Text(String(status))
            .font(DesignSystem.Fonts.mono(12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
            .accessibilityLabel("Response status \(status)")
    }
}

// MARK: - Supporting enums

private enum ComposerMainTab { case request, response }
private enum ComposerResponseTab { case body, headers }
