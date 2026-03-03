import SwiftUI

// MARK: - Supporting data types

struct FlowTimingData {
    let duration: TimeInterval?
    let requestBodySize: Int
    let responseBodySize: Int

    var formattedDuration: String {
        guard let d = duration else { return "—" }
        if d < 1 { return "\(Int((d * 1000).rounded())) ms" }
        if d < 10 { return d.formatted(.number.precision(.fractionLength(2))) + " s" }
        return d.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    static func formatBytes(_ count: Int) -> String {
        if count == 0 { return "0 bytes" }
        if count < 1024 { return "\(count) bytes" }
        if count < 1_048_576 { return String(format: "%.1f KB", Double(count) / 1024.0) }
        return String(format: "%.1f MB", Double(count) / 1_048_576.0)
    }
}

// MARK: - FlowPanel

struct FlowPanel: View {
    let title: String
    let method: String?
    let status: Int?
    let headers: [String: String]
    let queryParameters: [(String, String)]
    let bodyFlow: String?
    let emptyText: String
    let isMapped: Bool
    let colors: DesignSystem.ColorPalette
    var timingData: FlowTimingData? = nil
    var websocketMessages: [WebSocketMessage] = []

    @State private var detailTab: DetailTab = .body

    private var hasQueryParameters: Bool { !queryParameters.isEmpty }
    private var hasWebSocketMessages: Bool { !websocketMessages.isEmpty }
    private var tabs: [DetailTab] {
        var available: [DetailTab] = [.body, .headers]
        if hasQueryParameters {
            available.append(.query)
        }
        if hasWebSocketMessages {
            available.append(.messages)
        }
        if timingData != nil {
            available.append(.timing)
        }
        return available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(12)) {
            FlowPanelHeader(
                title: title,
                method: method,
                status: status,
                isMapped: isMapped,
                colors: colors,
                tabs: tabs,
                selection: $detailTab
            )

            Group {
                switch detailTab {
                case .headers:
                    HeadersList(headers: headers, colors: colors)
                case .query:
                    QueryParametersList(parameters: queryParameters, colors: colors)
                case .body:
                    BodyInspector(payload: bodyFlow, headers: headers, emptyText: emptyText, colors: colors)
                case .messages:
                    WebSocketMessagesPanel(messages: websocketMessages, colors: colors)
                case .timing:
                    if let timingData {
                        TimingView(timingData: timingData, colors: colors)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(DesignSystem.Metrics.scaled(12))
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(14), style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(14))
                        .stroke(colors.border.opacity(0.65), lineWidth: 1)
                )
        )
        .onAppear {
            guard !hasQueryParameters, detailTab == .query else { return }
            detailTab = .body
        }
        .onChange(of: hasQueryParameters) { _, hasQuery in
            if !hasQuery, detailTab == .query {
                detailTab = .body
            }
        }
        .onChange(of: hasWebSocketMessages) { _, hasMessages in
            if hasMessages, detailTab == .body {
                detailTab = .messages
            }
        }
    }
}

private struct FlowPanelHeader: View {
    let title: String
    let method: String?
    let status: Int?
    let isMapped: Bool
    let colors: DesignSystem.ColorPalette
    let tabs: [DetailTab]
    @Binding var selection: DetailTab

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
            HStack(alignment: .center, spacing: DesignSystem.Metrics.scaled(10)) {
                HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                    Text(title)
                        .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)

                    if let method {
                        MethodBadge(method: method)
                    }

                    if let status {
                        StatusBadge(status: status, colors: colors)
                    }

                    if isMapped {
                        Label("Mapped", systemImage: "pencil.and.outline")
                            .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                            .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                            .padding(.vertical, DesignSystem.Metrics.scaled(4))
                            .background(colors.accent.opacity(0.12))
                            .foregroundStyle(colors.accent)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                FlowPanelInlineTabs(tabs: tabs, selection: $selection, colors: colors)
            }

            Divider().overlay(colors.border.opacity(0.5))
        }
    }
}

private struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method.uppercased())
            .font(DesignSystem.Fonts.sans(12, weight: .bold))
            .foregroundStyle(color(for: method))
    }

    private func color(for method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "PATCH": return .purple
        case "DELETE": return .red
        default: return Color.primary
        }
    }
}

private struct FlowPanelInlineTabs: View {
    let tabs: [DetailTab]
    @Binding var selection: DetailTab
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(6)) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(DesignSystem.Fonts.sans(12, weight: selection == tab ? .semibold : .medium))
                        .foregroundStyle(selection == tab ? colors.textPrimary : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                        .padding(.vertical, DesignSystem.Metrics.scaled(4))
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8), style: .continuous)
                                .fill(selection == tab ? colors.surfaceElevated : colors.surface.opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                .stroke(selection == tab ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Headers
private struct HeadersList: View {
    let headers: [String: String]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        if headers.isEmpty {
            Text("No headers available")
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(10)) {
                    ForEach(headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }), id: \.key) { key, value in
                        HeaderRow(key: key, value: value, colors: colors)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HeaderRow: View {
    let key: String
    let value: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(4)) {
            Text(key)
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(DesignSystem.Fonts.mono(12))
                .textSelection(.enabled)
                .foregroundStyle(colors.textPrimary)
        }
        .padding(DesignSystem.Metrics.scaled(10))
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

// MARK: - Query parameters

private struct QueryParametersList: View {
    let parameters: [(String, String)]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        if parameters.isEmpty {
            Text("No query parameters")
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(10)) {
                    ForEach(Array(parameters.enumerated()), id: \.offset) { entry in
                        let item = entry.element
                        HeaderRow(key: item.0, value: item.1, colors: colors)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Body
private struct BodyInspector: View {
    let payload: String?
    let headers: [String: String]
    let emptyText: String
    let colors: DesignSystem.ColorPalette

    private let imagePreviewHeight: CGFloat = DesignSystem.Metrics.scaled(240)

    @State private var mode: BodyMode = .pretty
    @State private var renderedText: String = ""
    @State private var renderedImage: NSImage?
    @State private var cache = BodyRenderCache(source: nil)

    private var contentType: String {
        headers.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
    }

    private var isGRPC: Bool {
        contentType.lowercased().contains("application/grpc")
    }

    private var isGraphQL: Bool {
        guard let raw = payload, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["query"] != nil || json["mutation"] != nil || json["subscription"] != nil
    }

    private var availableModes: [BodyMode] {
        var modes: [BodyMode] = []
        if renderedImage != nil {
            modes.append(.image)
        }
        if isGraphQL {
            modes.append(.graphql)
        }
        if isGRPC {
            modes.append(.grpc)
        }
        modes.append(contentsOf: [.pretty, .raw, .hex])
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(12)) {
            BodyModePicker(mode: $mode, modes: availableModes, colors: colors)

            if renderedText.isEmpty && renderedImage == nil {
                Text(emptyText)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Group {
                    if mode == .image, let renderedImage {
                        Image(nsImage: renderedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: imagePreviewHeight, maxHeight: imagePreviewHeight, alignment: .center)
                            .padding(DesignSystem.Metrics.scaled(10))
                    } else {
                        CodeEditorView(
                            text: $renderedText,
                            isEditable: false
                        )
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .padding(DesignSystem.Metrics.scaled(10))
                    }
                }
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
        .onAppear(perform: refreshIfNeeded)
        .onChange(of: payload ?? "") { _ in
            // Reset cache when switching flow to avoid stale content.
            cache = BodyRenderCache(source: nil)
            refreshIfNeeded()
        }
        .onChange(of: mode) { _ in
            refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        let raw = (payload ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else {
            renderedText = ""
            renderedImage = nil
            return
        }

        renderedImage = BodyImageDecoder.decode(from: raw, contentType: contentType)

        if cache.source != raw {
            cache = BodyRenderCache(source: raw)
        }

        if renderedImage != nil, mode == .pretty {
            mode = .image
        }
        if renderedImage == nil, mode == .image {
            mode = .pretty
        }
        if isGraphQL, mode == .pretty {
            mode = .graphql
        }
        if isGRPC, mode == .pretty {
            mode = .grpc
        }

        switch mode {
        case .raw:
            renderedText = raw
        case .pretty:
            renderedText = cache.prettyPrinted ?? cache.pretty()
        case .hex:
            renderedText = cache.hexDump ?? cache.hex(contentTypeHint: contentType)
        case .image:
            renderedText = raw
        case .graphql:
            renderedText = cache.graphqlText ?? cache.graphql()
        case .grpc:
            renderedText = cache.grpcText ?? cache.grpc()
        }
    }
}

private struct BodyModePicker: View {
    @Binding var mode: BodyMode
    let modes: [BodyMode]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(8)) {
            ForEach(modes, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(DesignSystem.Fonts.sans(12, weight: mode == option ? .semibold : .medium))
                        .foregroundStyle(mode == option ? colors.textPrimary : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(10))
                        .padding(.vertical, DesignSystem.Metrics.scaled(5))
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                                .fill(mode == option ? colors.surfaceElevated : colors.surface.opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                                .stroke(mode == option ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BodyRenderCache {
    let source: String?
    private(set) var prettyPrinted: String?
    private(set) var hexDump: String?
    private(set) var graphqlText: String?
    private(set) var grpcText: String?

    init(source: String?) {
        self.source = source
    }

    mutating func pretty() -> String {
        if let prettyPrinted { return prettyPrinted }
        // Cache the expensive JSON formatting so the view doesn't recompute on every body toggle.
        let pretty = BodyRenderCache.makePretty(from: source) ?? (source ?? "")
        prettyPrinted = pretty
        return pretty
    }

    mutating func hex(contentTypeHint: String) -> String {
        if let hexDump { return hexDump }
        let hex = BodyRenderCache.makeHex(from: source, contentTypeHint: contentTypeHint) ?? (source ?? "")
        hexDump = hex
        return hex
    }

    mutating func graphql() -> String {
        if let graphqlText { return graphqlText }
        let result = BodyRenderCache.makeGraphQL(from: source) ?? (source ?? "")
        graphqlText = result
        return result
    }

    mutating func grpc() -> String {
        if let grpcText { return grpcText }
        let result = BodyRenderCache.makeGRPC(from: source) ?? (source ?? "")
        grpcText = result
        return result
    }

    private static func makeGraphQL(from source: String?) -> String? {
        guard let source,
              let data = source.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var lines: [String] = []

        if let operationName = json["operationName"] as? String, !operationName.isEmpty {
            lines.append("# Operation: \(operationName)\n")
        }

        if let query = json["query"] as? String {
            lines.append("# Query")
            lines.append(query.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let mutation = json["mutation"] as? String {
            lines.append("# Mutation")
            lines.append(mutation.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let subscription = json["subscription"] as? String {
            lines.append("# Subscription")
            lines.append(subscription.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let variables = json["variables"],
           let variablesData = try? JSONSerialization.data(withJSONObject: variables, options: .prettyPrinted),
           let variablesString = String(data: variablesData, encoding: .utf8) {
            lines.append("\n# Variables")
            lines.append(variablesString)
        }

        if let extensions = json["extensions"],
           let extData = try? JSONSerialization.data(withJSONObject: extensions, options: .prettyPrinted),
           let extString = String(data: extData, encoding: .utf8) {
            lines.append("\n# Extensions")
            lines.append(extString)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func makeGRPC(from source: String?) -> String? {
        guard let source else { return nil }
        // gRPC frames: 1 byte compressed flag + 4 bytes big-endian message length + payload
        guard let rawData = Data(base64Encoded: source, options: .ignoreUnknownCharacters),
              rawData.count >= 5
        else {
            return "# gRPC Frame\n# (binary payload — base64 encoded below)\n\n\(source)"
        }

        let compressed = rawData[0] == 1
        let messageLength = Int(rawData[1]) << 24 | Int(rawData[2]) << 16 | Int(rawData[3]) << 8 | Int(rawData[4])
        let payload = rawData.dropFirst(5)

        var lines = ["# gRPC Frame",
                     "  Compressed: \(compressed ? "yes" : "no")",
                     "  Message length: \(messageLength) bytes",
                     "  Payload bytes: \(payload.count)",
                     "",
                     "# Payload (hex)"]

        let bytes = payload.map { String(format: "%02X", $0) }
        let hexLines = stride(from: 0, to: bytes.count, by: 16).map { index -> String in
            let chunk = bytes[index..<min(index + 16, bytes.count)].joined(separator: " ")
            let lineNumber = String(format: "%04X", index)
            return "\(lineNumber)  \(chunk)"
        }
        lines.append(contentsOf: hexLines)

        return lines.joined(separator: "\n")
    }

    private static func makePretty(from source: String?) -> String? {
        guard let source,
              let data = source.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else { return nil }
        return prettyString
    }

    private static func makeHex(from source: String?) -> String? {
        makeHex(from: source, contentTypeHint: "")
    }

    private static func makeHex(from source: String?, contentTypeHint: String) -> String? {
        let decodedImageData = BodyImageDecoder.decodeData(from: source, contentType: contentTypeHint)
        let data = decodedImageData ?? source?.data(using: .utf8)
        guard let data, !data.isEmpty else { return nil }

        let bytes = data.map { String(format: "%02X", $0) }
        let lines = stride(from: 0, to: bytes.count, by: 16).map { index -> String in
            let chunk = bytes[index..<min(index + 16, bytes.count)].joined(separator: " ")
            let paddedChunk = chunk.padding(toLength: max(47, chunk.count), withPad: " ", startingAt: 0)
            let ascii = data[index..<min(index + 16, data.count)]
                .compactMap { byte -> String in
                    guard let scalar = UnicodeScalar(Int(byte)), scalar.isASCII, scalar.value >= 32 else {
                        return "."
                    }
                    return String(scalar)
                }
                .joined()
            let lineNumber = String(format: "%04X", index)
            return "\(lineNumber)  \(paddedChunk)  \(ascii)"
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Timing

private struct TimingView: View {
    let timingData: FlowTimingData
    let colors: DesignSystem.ColorPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(10)) {
                if let duration = timingData.duration {
                    VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
                        Text("Total Duration")
                            .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                            .foregroundStyle(colors.textSecondary)
                        Text(timingData.formattedDuration)
                            .font(DesignSystem.Fonts.mono(22, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(4))
                                .fill(colors.accent.opacity(0.25))
                                .frame(width: geo.size.width, height: DesignSystem.Metrics.scaled(6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(4))
                                        .fill(colors.accent)
                                        .frame(width: min(geo.size.width, geo.size.width * min(duration / 30.0, 1.0)))
                                    , alignment: .leading
                                )
                        }
                        .frame(height: DesignSystem.Metrics.scaled(6))
                    }
                    .padding(DesignSystem.Metrics.scaled(12))
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

                TimingStatRow(
                    icon: "arrow.up.circle",
                    label: "Request size",
                    value: FlowTimingData.formatBytes(timingData.requestBodySize),
                    colors: colors
                )
                TimingStatRow(
                    icon: "arrow.down.circle",
                    label: "Response size",
                    value: FlowTimingData.formatBytes(timingData.responseBodySize),
                    colors: colors
                )
            }
        }
    }
}

private struct TimingStatRow: View {
    let icon: String
    let label: String
    let value: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(10)) {
            Image(systemName: icon)
                .font(.system(size: DesignSystem.Metrics.scaled(16)))
                .foregroundStyle(colors.accent)
                .frame(width: DesignSystem.Metrics.scaled(20))
            VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(2)) {
                Text(label)
                    .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text(value)
                    .font(DesignSystem.Fonts.mono(13, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
            }
            Spacer()
        }
        .padding(DesignSystem.Metrics.scaled(10))
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

// MARK: - WebSocket Messages (placeholder — populated in Feature 6)

private struct WebSocketMessagesPanel: View {
    let messages: [WebSocketMessage]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
                ForEach(messages) { message in
                    WebSocketMessageRow(message: message, colors: colors)
                }
            }
        }
    }
}

private struct WebSocketMessageRow: View {
    let message: WebSocketMessage
    let colors: DesignSystem.ColorPalette
    @State private var isExpanded = false

    private var directionColor: Color {
        message.direction == .client ? colors.accent : colors.accentSecondary
    }

    private var directionIcon: String {
        message.direction == .client ? "arrow.up.right" : "arrow.down.left"
    }

    private var truncatedContent: String {
        let content = message.content
        if content.count <= 200 { return content }
        return String(content.prefix(200)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(6)) {
            HStack(spacing: DesignSystem.Metrics.scaled(8)) {
                Image(systemName: directionIcon)
                    .font(.system(size: DesignSystem.Metrics.scaled(12), weight: .semibold))
                    .foregroundStyle(directionColor)
                Text(message.type == .text ? "TEXT" : "BIN")
                    .font(DesignSystem.Fonts.mono(10, weight: .bold))
                    .padding(.horizontal, DesignSystem.Metrics.scaled(6))
                    .padding(.vertical, DesignSystem.Metrics.scaled(2))
                    .background(Capsule().fill(directionColor.opacity(0.12)))
                    .foregroundStyle(directionColor)
                Spacer()
                Text(formattedTimestamp(message.timestamp))
                    .font(DesignSystem.Fonts.mono(10))
                    .foregroundStyle(colors.textSecondary)
            }
            Text(isExpanded ? message.content : truncatedContent)
                .font(DesignSystem.Fonts.mono(12))
                .foregroundStyle(colors.textPrimary)
                .textSelection(.enabled)
            if message.content.count > 200 {
                Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                    .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Metrics.scaled(10))
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(10))
                        .stroke(colors.border, lineWidth: 1)
                )
        )
    }

    private func formattedTimestamp(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        return DateFormatter.cachedTime.string(from: date)
    }
}

// MARK: - Body Modes

private enum BodyMode: CaseIterable {
    case image, raw, pretty, hex, graphql, grpc

    var label: String {
        switch self {
        case .image: return "Image"
        case .raw: return "Raw"
        case .pretty: return "Pretty"
        case .hex: return "Hex"
        case .graphql: return "GraphQL"
        case .grpc: return "gRPC"
        }
    }
}

private enum BodyImageDecoder {
    private static func headerIsImage(_ contentType: String) -> Bool {
        let mime = contentType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return mime.lowercased().hasPrefix("image/")
    }

    static func decode(from source: String, contentType: String) -> NSImage? {
        guard let data = decodeData(from: source, contentType: contentType) else { return nil }
        return NSImage(data: data)
    }

    static func decodeData(from source: String?, contentType: String) -> Data? {
        guard let source else { return nil }
        if let dataUrl = DataURL.parse(source) {
            return dataUrl.data
        }
        guard headerIsImage(contentType) else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]), !data.isEmpty else { return nil }
        return data
    }

    private struct DataURL {
        let mime: String
        let data: Data

        static func parse(_ source: String) -> DataURL? {
            guard source.hasPrefix("data:") else { return nil }
            guard let commaIndex = source.firstIndex(of: ",") else { return nil }
            let metaStart = source.index(source.startIndex, offsetBy: 5)
            let meta = String(source[metaStart..<commaIndex])
            guard meta.contains(";base64") else { return nil }
            let mime = meta
                .split(separator: ";", maxSplits: 1)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "application/octet-stream"
            let b64 = String(source[source.index(after: commaIndex)...])
            guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]), !data.isEmpty else { return nil }
            return DataURL(mime: mime, data: data)
        }
    }
}

private enum DetailTab: String, CaseIterable {
    case headers = "Headers"
    case query = "Query"
    case body = "Body"
    case messages = "Messages"
    case timing = "Timing"
}
