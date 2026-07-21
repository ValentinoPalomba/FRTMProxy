import Foundation

enum ProtocolInspector {
    static func inspect(body: String?, headers: [String: String]) -> ProtocolInspectionResult? {
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        let contentType = normalizedHeaders["content-type"]?.lowercased() ?? ""
        let raw = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if contentType.contains("text/event-stream") {
            return inspectSSE(raw)
        }
        if contentType.contains("application/grpc") {
            return inspectGRPC(raw)
        }
        if contentType.contains("application/x-www-form-urlencoded") {
            return inspectForm(raw)
        }
        if contentType.contains("multipart/") {
            return inspectMultipart(raw, contentType: contentType)
        }
        if contentType.contains("html") {
            return single(.html, content: raw)
        }
        if contentType.contains("xml") || raw.hasPrefix("<?xml") {
            return single(.xml, content: raw)
        }
        if let result = inspectJSON(raw) {
            return result
        }
        if let result = inspectJWT(raw, authorization: normalizedHeaders["authorization"]) {
            return result
        }
        if let result = inspectCookies(normalizedHeaders) {
            return result
        }
        guard !raw.isEmpty else { return nil }
        return single(contentType.hasPrefix("text/") ? .text : .binary, content: raw)
    }

    private static func inspectJSON(_ raw: String) -> ProtocolInspectionResult? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        let pretty = prettyJSON(object) ?? raw

        if let dictionary = object as? [String: Any],
           dictionary["query"] != nil || dictionary["mutation"] != nil || dictionary["subscription"] != nil {
            let operation = dictionary["operationName"] as? String
            var sections = [ProtocolInspectionSection(id: "document", title: "Document", content: pretty)]
            if let variables = dictionary["variables"], let rendered = prettyJSON(variables) {
                sections.append(.init(id: "variables", title: "Variables", content: rendered))
            }
            return .init(kind: .graphQL, summary: operation, sections: sections)
        }
        return .init(kind: .json, summary: nil, sections: [.init(id: "body", title: "Body", content: pretty)])
    }

    private static func inspectJWT(_ raw: String, authorization: String?) -> ProtocolInspectionResult? {
        let candidate: String
        if let authorization, authorization.lowercased().hasPrefix("bearer ") {
            candidate = String(authorization.dropFirst(7))
        } else {
            candidate = raw
        }
        let segments = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let header = decodeBase64URL(String(segments[0])),
              let payload = decodeBase64URL(String(segments[1]))
        else { return nil }
        return .init(
            kind: .jwt,
            summary: "Signature is not verified",
            sections: [
                .init(id: "header", title: "Header", content: prettyJSONData(header) ?? String(decoding: header, as: UTF8.self)),
                .init(id: "payload", title: "Payload", content: prettyJSONData(payload) ?? String(decoding: payload, as: UTF8.self)),
                .init(id: "signature", title: "Signature", content: String(segments[2]))
            ]
        )
    }

    private static func inspectCookies(_ headers: [String: String]) -> ProtocolInspectionResult? {
        let values = [headers["cookie"], headers["set-cookie"]].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return .init(
            kind: .cookies,
            summary: "\(values.count) cookie header(s)",
            sections: values.enumerated().map { index, value in
                .init(id: "cookie-\(index)", title: index == 0 ? "Cookies" : "Set-Cookie", content: value)
            }
        )
    }

    private static func inspectForm(_ raw: String) -> ProtocolInspectionResult {
        let items = URLComponents(string: "?\(raw)")?.queryItems ?? []
        let content = items.map { "\($0.name) = \($0.value ?? "")" }.joined(separator: "\n")
        return single(.formURLEncoded, content: content.isEmpty ? raw : content)
    }

    private static func inspectMultipart(_ raw: String, contentType: String) -> ProtocolInspectionResult {
        guard let boundaryRange = contentType.range(of: "boundary=") else {
            return single(.multipart, content: raw)
        }
        let boundary = contentType[boundaryRange.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let parts = raw.components(separatedBy: "--\(boundary)")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "--" }
        return .init(
            kind: .multipart,
            summary: "\(parts.count) part(s)",
            sections: parts.enumerated().map { .init(id: "part-\($0.offset)", title: "Part \($0.offset + 1)", content: $0.element) }
        )
    }

    private static func inspectSSE(_ raw: String) -> ProtocolInspectionResult {
        let events = raw.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return .init(
            kind: .serverSentEvents,
            summary: "\(events.count) event(s)",
            sections: events.enumerated().map { .init(id: "event-\($0.offset)", title: "Event \($0.offset + 1)", content: $0.element) }
        )
    }

    private static func inspectGRPC(_ raw: String) -> ProtocolInspectionResult {
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters), data.count >= 5 else {
            return single(.grpc, content: raw)
        }
        var cursor = 0
        var sections: [ProtocolInspectionSection] = []
        while cursor + 5 <= data.count {
            let compressed = data[cursor] == 1
            let length = Int(data[cursor + 1]) << 24 | Int(data[cursor + 2]) << 16 | Int(data[cursor + 3]) << 8 | Int(data[cursor + 4])
            guard length >= 0, cursor + 5 + length <= data.count else { break }
            let payload = data.subdata(in: (cursor + 5)..<(cursor + 5 + length))
            let decoded = ProtobufWireDecoder.decode(payload) ?? payload.map { String(format: "%02x", $0) }.joined()
            sections.append(.init(id: "message-\(sections.count)", title: "Message \(sections.count + 1) · \(compressed ? "compressed" : "plain")", content: decoded))
            cursor += 5 + length
        }
        return .init(kind: .grpc, summary: "\(sections.count) message(s)", sections: sections.isEmpty ? [.init(id: "raw", title: "Raw", content: raw)] : sections)
    }

    private static func single(_ kind: InspectedProtocolKind, content: String) -> ProtocolInspectionResult {
        .init(kind: kind, summary: nil, sections: [.init(id: "body", title: "Body", content: content)])
    }

    private static func prettyJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func prettyJSONData(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return prettyJSON(object)
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacing("-", with: "+").replacing("_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }
}
