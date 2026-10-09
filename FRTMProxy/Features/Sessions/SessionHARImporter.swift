import Foundation

enum SessionHARImporter {
    static let maximumFileBytes = 32 * 1024 * 1024
    static let maximumEntries = 10_000
    static let previewBytes = 2 * 1024 * 1024

    struct Item: Sendable {
        var flow: MitmFlow
        let requestBody: Data?
        let responseBody: Data?
    }

    struct Prepared: Sendable {
        let items: [Item]
        var startedAt: Date { Date(timeIntervalSince1970: items.compactMap { $0.flow.requestTimestamp }.min() ?? 0) }
        var endedAt: Date { Date(timeIntervalSince1970: items.compactMap { $0.flow.responseTimestamp ?? $0.flow.requestTimestamp }.max() ?? 0) }
    }

    static func prepare(_ data: Data) throws -> Prepared {
        guard data.count <= maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
        let file = try HARCollectionConverter.harDecoder.decode(HARFile.self, from: data)
        guard file.log.version == "1.2", !file.log.entries.isEmpty,
              file.log.entries.count <= maximumEntries else { throw CocoaError(.fileReadCorruptFile) }
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let log = document?["log"] as? [String: Any]
        let extensions = log?["entries"] as? [[String: Any]] ?? []
        let items = try file.log.entries.enumerated().map { index, entry -> Item in
            guard let start = entry.startedDateTime, start >= .distantPast, start <= .distantFuture, let url = URL(string: entry.request.url),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                  (0...599).contains(entry.response.status) else { throw CocoaError(.fileReadCorruptFile) }
            let requestHeaders = try fields(entry.request.headers)
            let responseHeaders = try fields(entry.response.headers)
            let requestBody = try body(entry.request.postData?.text, encoding: entry.request.postData?.encoding)
            let responseBody = try body(entry.response.content?.text, encoding: entry.response.content?.encoding)
            let extra = extensions.indices.contains(index) ? extensions[index] : [:]
            var flow = MitmFlow(id: UUID().uuidString, event: extra["_captureEvent"] as? String ?? "response")
            flow.captureError = extra["_captureError"] as? String
            flow.timestamp = start.timeIntervalSince1970
            flow.requestTimestamp = flow.timestamp
            if let time = entry.time, time.isFinite, time >= 0 {
                let end = start.timeIntervalSince1970 + time / 1000
                guard end.isFinite, end <= Date.distantFuture.timeIntervalSince1970 else { throw CocoaError(.fileReadCorruptFile) }
                flow.responseTimestamp = end
            }
            let method = entry.request.method ?? "GET"
            guard HTTPHeaderField.isValidName(method) else { throw CocoaError(.fileReadCorruptFile) }
            flow.request = .init(method: method, url: entry.request.url, headers: dictionary(requestHeaders),
                                 body: preview(requestBody), httpVersion: entry.request.httpVersion,
                                 headerFields: requestHeaders, byteCount: size(entry.request.bodySize, fallback: requestBody),
                                 bodyTruncated: requestBody.map { $0.count > previewBytes })
            flow.response = .init(status: entry.response.status, headers: dictionary(responseHeaders),
                                  body: preview(responseBody), httpVersion: entry.response.httpVersion,
                                  headerFields: responseHeaders, byteCount: size(entry.response.bodySize, fallback: responseBody),
                                  bodyTruncated: responseBody.map { $0.count > previewBytes })
            return Item(flow: flow, requestBody: requestBody, responseBody: responseBody)
        }
        return Prepared(items: items)
    }

    private static func fields(_ headers: [HARHeader]?) throws -> [HTTPHeaderField] {
        let result = (headers ?? []).map { HTTPHeaderField(name: $0.name, value: $0.value) }
        guard result.count <= 128, result.allSatisfy({ HTTPHeaderField.isValidName($0.name) && !$0.value.contains("\r") && !$0.value.contains("\n") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }

    private static func dictionary(_ fields: [HTTPHeaderField]) -> [String: String] {
        fields.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    private static func body(_ text: String?, encoding: String?) throws -> Data? {
        guard let text else { return nil }
        guard let encoding, !encoding.isEmpty else { return Data(text.utf8) }
        guard encoding.lowercased() == "base64", let data = Data(base64Encoded: text) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    private static func preview(_ body: Data?) -> String? {
        guard let body else { return nil }
        let bytes = Data(body.prefix(previewBytes))
        return String(data: bytes, encoding: .utf8) ?? "data:application/octet-stream;base64," + bytes.base64EncodedString()
    }

    private static func size(_ recorded: Int?, fallback: Data?) -> Int? {
        if let recorded, recorded >= 0 { return recorded }
        return fallback?.count
    }
}
