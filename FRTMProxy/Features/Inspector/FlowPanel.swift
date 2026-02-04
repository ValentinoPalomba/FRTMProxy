import Foundation
import SwiftUI

struct FlowPanel: View {
    let title: String
    let method: String?
    let status: Int?
    let headers: [String: String]
    let queryParameters: [(String, String)]
    let bodyFlow: String?
    let emptyText: String
    let isMapped: Bool
    let showsParserSelector: Bool
    let colors: DesignSystem.ColorPalette

    @State private var detailTab: DetailTab = .body

    private var hasQueryParameters: Bool { !queryParameters.isEmpty }
    private var tabs: [DetailTab] {
        var available: [DetailTab] = [.body, .headers]
        if hasQueryParameters {
            available.append(.query)
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
                    BodyInspector(
                        payload: bodyFlow,
                        headers: headers,
                        emptyText: emptyText,
                        showsParserSelector: showsParserSelector,
                        colors: colors
                    )
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
    let showsParserSelector: Bool
    let colors: DesignSystem.ColorPalette

    private let imagePreviewHeight: CGFloat = DesignSystem.Metrics.scaled(240)

    @State private var mode: BodyMode = .pretty
    @State private var parser: PrettyParser = .json
    @State private var renderedText: String = ""
    @State private var renderedImage: NSImage?
    @State private var cache = BodyRenderCache(source: nil)

    private var contentType: String {
        headers.first(where: { $0.key.lowercased() == "content-type" })?.value ?? ""
    }

    private var availableModes: [BodyMode] {
        var modes: [BodyMode] = []
        if renderedImage != nil {
            modes.append(.image)
        }
        modes.append(contentsOf: [.pretty, .raw, .hex])
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Metrics.scaled(12)) {
            BodyModePicker(
                mode: $mode,
                modes: availableModes,
                parser: showsParserSelector ? $parser : nil,
                colors: colors
            )

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
                            isEditable: false,
                            mimeType: editorMimeType
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
        .onChange(of: parser) { _ in
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

        switch mode {
        case .raw:
            renderedText = raw
        case .pretty:
            renderedText = cache.prettyPrinted(parser: parser) ?? cache.pretty(using: parser)
        case .hex:
            renderedText = cache.hexDump ?? cache.hex(contentTypeHint: contentType)
        case .image:
            renderedText = raw
        }
    }

    private var editorMimeType: String {
        switch mode {
        case .hex:
            return "text/plain"
        case .raw, .pretty:
            return parser.mimeType
        case .image:
            return "text/plain"
        }
    }
}

private struct BodyModePicker: View {
    @Binding var mode: BodyMode
    let modes: [BodyMode]
    let parser: Binding<PrettyParser>?
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

            if let parser {
                Spacer(minLength: DesignSystem.Metrics.scaled(10))
                PrettyParserPicker(parser: parser, colors: colors)
            }
        }
    }
}

private struct PrettyParserPicker: View {
    @Binding var parser: PrettyParser
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Metrics.scaled(6)) {
            Text("Parser")
                .font(DesignSystem.Fonts.sans(11, weight: .semibold))
                .foregroundStyle(colors.textSecondary)

            ForEach(PrettyParser.allCases, id: \.self) { option in
                Button {
                    parser = option
                } label: {
                    Text(option.label)
                        .font(DesignSystem.Fonts.sans(11, weight: parser == option ? .semibold : .medium))
                        .foregroundStyle(parser == option ? colors.textPrimary : colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Metrics.scaled(8))
                        .padding(.vertical, DesignSystem.Metrics.scaled(4))
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                .fill(parser == option ? colors.surfaceElevated : colors.surface.opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius(8))
                                .stroke(parser == option ? colors.border.opacity(0.9) : colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BodyRenderCache {
    let source: String?
    private(set) var prettyPrintedJSON: String?
    private(set) var prettyPrintedXML: String?
    private(set) var hexDump: String?

    init(source: String?) {
        self.source = source
    }

    func prettyPrinted(parser: PrettyParser) -> String? {
        switch parser {
        case .json:
            return prettyPrintedJSON
        case .xml:
            return prettyPrintedXML
        }
    }

    mutating func pretty(using parser: PrettyParser) -> String {
        if let cached = prettyPrinted(parser: parser) {
            return cached
        }

        let pretty = BodyRenderCache.makePretty(from: source, parser: parser) ?? (source ?? "")

        switch parser {
        case .json:
            prettyPrintedJSON = pretty
        case .xml:
            prettyPrintedXML = pretty
        }

        return pretty
    }

    mutating func hex(contentTypeHint: String) -> String {
        if let hexDump { return hexDump }
        let hex = BodyRenderCache.makeHex(from: source, contentTypeHint: contentTypeHint) ?? (source ?? "")
        hexDump = hex
        return hex
    }

    private static func makePretty(from source: String?, parser: PrettyParser) -> String? {
        switch parser {
        case .json:
            return makeJSONPretty(from: source)
        case .xml:
            return makeXMLPretty(from: source)
        }
    }

    private static func makeJSONPretty(from source: String?) -> String? {
        guard let source,
              let data = source.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else { return nil }
        return prettyString
    }

    private static func makeXMLPretty(from source: String?) -> String? {
        guard let source else { return nil }
        guard let document = try? XMLDocument(xmlString: source, options: .nodePreserveAll) else { return nil }
        let data = document.xmlData(options: .nodePrettyPrint)
        return String(data: data, encoding: .utf8)
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

private enum BodyMode: CaseIterable {
    case image, raw, pretty, hex

    var label: String {
        switch self {
        case .image: return "Image"
        case .raw: return "Raw"
        case .pretty: return "Pretty"
        case .hex: return "Hex"
        }
    }
}

private enum PrettyParser: CaseIterable {
    case json
    case xml

    var label: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        }
    }

    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .xml: return "application/xml"
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
}
