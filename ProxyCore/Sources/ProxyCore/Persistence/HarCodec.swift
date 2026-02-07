import Foundation

public enum HarCodec {
    public static func toHar(flows: [HistoryFlow], creatorName: String = "ProxyCore", creatorVersion: String? = nil) throws -> Data {
        let entries = flows.map { HAREntry.from(flow: $0) }
        let har = HARFile(
            log: HARLog(
                version: "1.2",
                creator: HARCreator(name: creatorName, version: creatorVersion),
                entries: entries
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom(encodeHARDate(_:to:))
        return try encoder.encode(har)
    }

    public static func fromHar(_ data: Data) throws -> HARFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeHARDate(from:))
        return try decoder.decode(HARFile.self, from: data)
    }
}

// MARK: - HAR Models (minimal, spec-compatible)

public struct HARFile: Codable, Sendable, Hashable {
    public var log: HARLog
}

public struct HARLog: Codable, Sendable, Hashable {
    public var version: String?
    public var creator: HARCreator?
    public var entries: [HAREntry]
}

public struct HARCreator: Codable, Sendable, Hashable {
    public var name: String
    public var version: String?
}

public struct HAREntry: Codable, Sendable, Hashable {
    public var startedDateTime: Date
    public var time: Double
    public var request: HARRequest
    public var response: HARResponse

    // Cache/timings are optional in HAR; keep minimal.
    public var cache: [String: String]?
    public var timings: [String: Double]?

    static func from(flow: HistoryFlow) -> HAREntry {
        let started = flow.startedAt
        let response = flow.response

        let timeMs: Double = 0
        // NOTE: ProxyCore currently doesn't track timing breakdown; keep time=0 for now.

        return HAREntry(
            startedDateTime: started,
            time: timeMs,
            request: HARRequest.from(flow: flow),
            response: HARResponse.from(flow: flow),
            cache: nil,
            timings: nil
        )
    }
}

public struct HARRequest: Codable, Sendable, Hashable {
    public var method: String
    public var url: String
    public var httpVersion: String?
    public var headers: [HARNameValue]?
    public var queryString: [HARNameValue]?
    public var cookies: [HARCookie]?
    public var headersSize: Int?
    public var bodySize: Int?
    public var postData: HARPostData?

    static func from(flow: HistoryFlow) -> HARRequest {
        let url = flow.request.url
        let queryItems = URL(string: url).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let qs = queryItems.map { HARNameValue(name: $0.name, value: $0.value ?? "") }

        let headers = flow.request.headers.map { HARNameValue(name: $0.key, value: $0.value) }

        let bodyData = flow.request.bodyBase64.flatMap { Data(base64Encoded: $0) }
        let postData = bodyData.flatMap { data -> HARPostData? in
            guard !data.isEmpty else { return nil }
            let mime = flow.request.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
            let (text, encoding) = HarBody.encodeBodyText(data)
            return HARPostData(mimeType: mime ?? "application/octet-stream", text: text, encoding: encoding)
        }

        return HARRequest(
            method: flow.request.method,
            url: url,
            httpVersion: flow.httpVersion.rawValue,
            headers: headers.isEmpty ? nil : headers,
            queryString: qs.isEmpty ? nil : qs,
            cookies: nil,
            headersSize: nil,
            bodySize: flow.request.rawBodySize,
            postData: postData
        )
    }
}

public struct HARResponse: Codable, Sendable, Hashable {
    public var status: Int
    public var statusText: String?
    public var httpVersion: String?
    public var headers: [HARNameValue]?
    public var cookies: [HARCookie]?
    public var content: HARContent?
    public var redirectURL: String?
    public var headersSize: Int?
    public var bodySize: Int?

    static func from(flow: HistoryFlow) -> HARResponse {
        let res = flow.response
        let status = res?.statusCode ?? 0
        let headers = (res?.headers ?? [:]).map { HARNameValue(name: $0.key, value: $0.value) }

        let bodyData = res?.bodyBase64.flatMap { Data(base64Encoded: $0) } ?? Data()
        let mime = (res?.headers ?? [:]).first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
        let content: HARContent? = {
            guard res != nil else { return nil }
            let (text, encoding) = HarBody.encodeBodyText(bodyData)
            return HARContent(size: bodyData.count, mimeType: mime ?? "application/octet-stream", text: text, encoding: encoding)
        }()

        return HARResponse(
            status: status,
            statusText: nil,
            httpVersion: flow.httpVersion.rawValue,
            headers: headers.isEmpty ? nil : headers,
            cookies: nil,
            content: content,
            redirectURL: nil,
            headersSize: nil,
            bodySize: res?.rawBodySize
        )
    }
}

public struct HARContent: Codable, Sendable, Hashable {
    public var size: Int
    public var mimeType: String?
    public var text: String?
    public var encoding: String?
}

public struct HARPostData: Codable, Sendable, Hashable {
    public var mimeType: String
    public var text: String?
    public var encoding: String?
}

public struct HARNameValue: Codable, Sendable, Hashable {
    public var name: String
    public var value: String
}

public struct HARCookie: Codable, Sendable, Hashable {
    public var name: String
    public var value: String
}

// MARK: - Helpers

private enum HarBody {
    static func encodeBodyText(_ data: Data) -> (text: String?, encoding: String?) {
        guard !data.isEmpty else { return (nil, nil) }
        if let s = String(data: data, encoding: .utf8) {
            return (s, nil)
        }
        return (data.base64EncodedString(), "base64")
    }
}

private func encodeHARDate(_ date: Date, to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    try container.encode(formatter.string(from: date))
}

private func decodeHARDate(from decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }

    // Fallback without fractional seconds.
    let fallback = ISO8601DateFormatter()
    fallback.formatOptions = [.withInternetDateTime]
    if let date = fallback.date(from: string) {
        return date
    }

    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid HAR date: \(string)")
}

