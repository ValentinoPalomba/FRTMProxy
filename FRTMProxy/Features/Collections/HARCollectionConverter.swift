import Foundation

enum HARCollectionConverter {
    static func exportHAR(collection: MapCollection) -> HARFile {
        let entries: [HAREntry] = collection.rules.map { rule in
            let requestURL = rule.request?.url ?? normalizedURLString(from: rule)
            let requestMethod = (rule.request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "GET"
            let requestHeaders = (rule.request?.headers ?? [:])
                .sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
                .map { HARHeader(name: $0.key, value: $0.value) }
            let requestQuery = HARQueryItem.items(from: requestURL)
            let requestContentType = rule.request?.headers.first(where: { $0.key.lowercased() == "content-type" })?.value
            let requestBody = rule.request?.body

            let headers = rule.headers
                .sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
                .map { HARHeader(name: $0.key, value: $0.value) }

            let mimeType = rule.headers.first(where: { $0.key.lowercased() == "content-type" })?.value

            return HAREntry(
                startedDateTime: collection.createdAt,
                time: 0,
                request: HARRequest(
                    method: requestMethod,
                    url: requestURL,
                    httpVersion: "HTTP/1.1",
                    headers: requestHeaders,
                    queryString: requestQuery,
                    cookies: nil,
                    headersSize: -1,
                    bodySize: requestBody?.data(using: .utf8)?.count ?? 0,
                    postData: requestBody.map { body in
                        HARPostData(mimeType: requestContentType, text: body, params: nil)
                    }
                ),
                response: HARResponse(
                    status: rule.status,
                    statusText: nil,
                    httpVersion: "HTTP/1.1",
                    headers: headers,
                    cookies: nil,
                    content: HARContent(
                        size: rule.body.data(using: .utf8)?.count,
                        mimeType: mimeType,
                        text: rule.body,
                        encoding: nil
                    ),
                    redirectURL: nil,
                    headersSize: -1,
                    bodySize: rule.body.data(using: .utf8)?.count
                )
            )
        }

        return HARFile(
            log: HARLog(
                version: "1.2",
                creator: HARCreator(name: "FRTMProxy", version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String),
                entries: entries
            )
        )
    }

    static func importCollection(from harData: Data, name: String, createdAt: Date = Date()) throws -> MapCollection {
        let file = try harDecoder.decode(HARFile.self, from: harData)
        let entries = file.log.entries

        var rules: [MapRule] = []
        var usedKeys = Set<String>()
        for entry in entries {
            let requestMethod = entry.request.method?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "GET"
            let requestURL = entry.request.url
            let requestHeaders = dictionary(from: entry.request.headers)
            let requestBody = entry.request.postData?.text

            guard let url = URL(string: requestURL),
                  let host = url.host else { continue }
            let path = url.path.isEmpty ? "/" : url.path
            let preferredKey = MapRuleKeyBuilder.makeKey(
                host: host,
                path: path,
                method: requestMethod,
                url: requestURL,
                headers: requestHeaders,
                body: requestBody
            )
            let key = MapRuleKeyBuilder.disambiguatedKey(preferredKey: preferredKey, existingKeys: usedKeys)
            usedKeys.insert(key)
            let scheme = url.scheme
            let body = decodedBody(from: entry.response.content)
            let headers = dictionary(from: entry.response.headers)

            rules.append(MapRule(
                key: key,
                host: host,
                path: path,
                scheme: scheme,
                request: MapRuleRequest(method: requestMethod, url: requestURL, headers: requestHeaders, body: requestBody),
                body: body,
                status: entry.response.status,
                headers: headers,
                isEnabled: true
            ))
        }

        return MapCollection(
            name: name,
            createdAt: createdAt,
            isEnabled: false,
            enabledAt: nil,
            rules: rules
        )
    }

    static func harEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom(encodeHARDate(_:to:))
        return encoder
    }

    static var harDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeHARDate(from:))
        return decoder
    }

    private static func normalizedURLString(from rule: MapRule) -> String {
        let scheme = (rule.scheme?.isEmpty ?? true) ? "https" : (rule.scheme ?? "https")
        let path = rule.path.isEmpty ? "/" : rule.path
        return "\(scheme)://\(rule.host)\(path)"
    }

    private static func dictionary(from headers: [HARHeader]?) -> [String: String] {
        guard let headers else { return [:] }
        var result: [String: String] = [:]
        for header in headers {
            result[header.name] = header.value
        }
        return result
    }

    private static func decodedBody(from content: HARContent?) -> String {
        guard let content else { return "" }
        guard let text = content.text else { return "" }
        guard (content.encoding ?? "").lowercased() == "base64" else { return text }

        guard let data = Data(base64Encoded: text) else { return text }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Contenuto binario (immagini, gzip, protobuf…): conservalo come data URL
        // — coerente con come il bridge rappresenta i body binari — invece di
        // restituire il base64 grezzo o una stringa vuota.
        let mime = content.mimeType ?? "application/octet-stream"
        return "data:\(mime);base64,\(text)"
    }

    private static func encodeHARDate(_ date: Date, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(harDateFormatter.string(from: date))
    }

    private static func decodeHARDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = harDateFormatter.date(from: string) {
            return date
        }

        if let date = fallbackHarDateFormatter.date(from: string) {
            return date
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid HAR date: \(string)")
    }

    private static let harDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackHarDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension HARQueryItem {
    static func items(from urlString: String) -> [HARQueryItem]? {
        guard let components = URLComponents(string: urlString) else { return nil }
        let items = (components.queryItems ?? []).map { HARQueryItem(name: $0.name, value: $0.value) }
        return items.isEmpty ? nil : items
    }
}
