import SwiftUI

// MARK: - RequestComposerView

struct RequestComposerView: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    let proxyPort: Int?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            composerHeader
            Divider().overlay(colors.border.opacity(0.7))

            HStack(spacing: 0) {
                requestCard
                    .frame(maxWidth: .infinity)
                Divider().overlay(colors.border.opacity(0.7))
                responseCard
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            composerFooter
        }
        .background(colors.surface)
    }

    // MARK: - Header

    private var composerHeader: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(12)) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: DesignSystem.Metrics.scaled(16), weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("Compose Request")
                .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            Spacer()
            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { onClose() }
        }
        .padding(DesignSystem.Metrics.scaled(16))
        .background(colors.surfaceElevated)
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        VStack(spacing: DesignSystem.Metrics.scaled(8)) {
            methodPicker
            TextField("https://example.com/api/endpoint", text: $viewModel.urlString)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                .font(DesignSystem.Fonts.mono(12))
                .onSubmit { sendRequest() }
        }
    }

    private var methodPicker: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(4)) {
            ForEach(RequestComposerViewModel.httpMethods, id: \.self) { method in
                let isSelected = viewModel.method == method
                Button { viewModel.method = method } label: {
                    Text(method)
                        .font(DesignSystem.Fonts.mono(11, weight: .bold))
                        .foregroundStyle(isSelected ? methodColor(method) : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                        .padding(.vertical, DesignSystem.Metrics.scaled(5))
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(7))
                                .fill(isSelected ? methodColor(method).opacity(0.12) : colors.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(7))
                                .stroke(isSelected ? methodColor(method).opacity(0.5) : colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "PATCH": return .purple
        case "DELETE": return .red
        default: return colors.textPrimary
        }
    }

    // MARK: - Request Card

    private var requestCard: some View {
        ComposerCard(title: "Request", colors: colors) {
            VStack(spacing: DesignSystem.Metrics.scaled(12)) {
                urlBar
                ComposerRequestBody(viewModel: viewModel, colors: colors)
            }
        }
    }

    // MARK: - Response Card

    private var responseCard: some View {
        ComposerCard(title: "Response", colors: colors) {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: DesignSystem.Metrics.scaled(12)) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Sending request...")
                            .font(DesignSystem.Fonts.sans(12, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: DesignSystem.Metrics.scaled(8)) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundStyle(colors.danger)
                        Text(error)
                            .font(DesignSystem.Fonts.sans(12, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.responseStatus != nil {
                    ComposerResponseBody(viewModel: viewModel, colors: colors)
                } else {
                    VStack(spacing: DesignSystem.Metrics.scaled(8)) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(colors.textSecondary.opacity(0.5))
                        Text("Send a request to see the response")
                            .font(DesignSystem.Fonts.sans(12, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Footer

    private var composerFooter: some View {
        HStack {
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, DesignSystem.Metrics.scaled(4))
            }
            ControlButton(
                title: "Send",
                systemImage: "paperplane.fill",
                style: .filled(colors),
                disabled: viewModel.isLoading || viewModel.urlString.isEmpty
            ) {
                sendRequest()
            }
        }
        .padding(.horizontal, DesignSystem.Metrics.scaled(16))
        .padding(.vertical, DesignSystem.Metrics.scaled(10))
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
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(12)) {
            Text(title)
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, DesignSystem.Metrics.scaled(16))
                .padding(.top, DesignSystem.Metrics.scaled(14))

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, DesignSystem.Metrics.scaled(16))
                .padding(.bottom, DesignSystem.Metrics.scaled(14))
        }
        .background(colors.surface)
    }
}

// MARK: - ComposerRequestBody

private struct ComposerRequestBody: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    @State private var tab: ComposerRequestTab = .body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
            HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                tabButton(.body)
                tabButton(.headers)
                Spacer()
            }

            Divider().overlay(colors.border.opacity(0.5))

            switch tab {
            case .body:
                TextEditor(text: $viewModel.requestBody)
                    .font(DesignSystem.Fonts.mono(12))
                    .scrollContentBackground(.hidden)
                    .background(colors.surfaceElevated)
                    .foregroundStyle(colors.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                            .stroke(colors.border.opacity(0.7), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .headers:
                ComposerHeadersEditor(viewModel: viewModel, colors: colors)
            }
        }
    }

    private func tabButton(_ t: ComposerRequestTab) -> some View {
        Button { tab = t } label: {
            Text(t.label)
                .font(DesignSystem.Fonts.sans(12, weight: tab == t ? .semibold : .medium))
                .foregroundStyle(tab == t ? colors.textPrimary : colors.textSecondary)
                .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                .padding(.vertical, DesignSystem.Metrics.scaled(4))
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                        .fill(tab == t ? colors.surfaceElevated : colors.surface.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                        .stroke(tab == t ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ComposerHeadersEditor

private struct ComposerHeadersEditor: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Metrics.scaled(6)) {
                    ForEach($viewModel.requestHeaders) { $row in
                        HStack(spacing: DesignSystem.Metrics.scaled(6)) {
                            TextField("Key", text: $row.key)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                                .font(DesignSystem.Fonts.mono(11))
                                .frame(maxWidth: .infinity)
                            TextField("Value", text: $row.value)
                                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                                .font(DesignSystem.Fonts.mono(11))
                                .frame(maxWidth: .infinity)
                            Button {
                                viewModel.requestHeaders.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(colors.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            ControlButton(title: "Add Header", systemImage: "plus", style: .ghost(colors)) {
                viewModel.addHeaderRow()
            }
        }
    }
}

// MARK: - ComposerResponseBody

private struct ComposerResponseBody: View {
    @ObservedObject var viewModel: RequestComposerViewModel
    let colors: DesignSystem.ColorPalette
    @State private var tab: ComposerResponseTab = .body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
            HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                if let status = viewModel.responseStatus {
                    ComposerStatusBadge(status: status, colors: colors)
                }
                Spacer()
                tabButton(.body)
                tabButton(.headers)
            }

            Divider().overlay(colors.border.opacity(0.5))

            switch tab {
            case .body:
                ScrollView([.vertical, .horizontal]) {
                    Text(prettyBody)
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .headers:
                if viewModel.responseHeaders.isEmpty {
                    Text("No headers")
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(8)) {
                            ForEach(
                                viewModel.responseHeaders.sorted { $0.key.lowercased() < $1.key.lowercased() },
                                id: \.key
                            ) { key, value in
                                VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(3)) {
                                    Text(key)
                                        .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                                        .foregroundStyle(colors.textSecondary)
                                    Text(value)
                                        .font(DesignSystem.Fonts.mono(12))
                                        .foregroundStyle(colors.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .padding(DesignSystem.Metrics.scaled(10))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                                        .fill(colors.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
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

    private func tabButton(_ t: ComposerResponseTab) -> some View {
        Button { tab = t } label: {
            Text(t.label)
                .font(DesignSystem.Fonts.sans(12, weight: tab == t ? .semibold : .medium))
                .foregroundStyle(tab == t ? colors.textPrimary : colors.textSecondary)
                .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                .padding(.vertical, DesignSystem.Metrics.scaled(4))
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                        .fill(tab == t ? colors.surfaceElevated : colors.surface.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                        .stroke(tab == t ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
            .font(DesignSystem.Fonts.mono(12, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, DesignSystem.Metrics.scaled(8))
            .padding(.vertical, DesignSystem.Metrics.scaled(4))
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Supporting enums

private enum ComposerRequestTab { case body, headers
    var label: String { self == .body ? "Body" : "Headers" }
}
private enum ComposerResponseTab { case body, headers
    var label: String { self == .body ? "Body" : "Headers" }
}
