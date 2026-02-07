import Foundation

/// ProxyPin-style "single entry" HAR-ish payload used by ReportServerInterceptor.
struct ReportHarEntry: Codable, Sendable {
    var startedDateTime: String
    var time: Int
    var pageref: String

    var id: String
    var app: ProxyProcessInfo?

    var request: ReportHarRequest
    var response: ReportHarResponse

    var cache: [String: String]
    var timings: ReportHarTimings
    var serverIPAddress: String

    enum CodingKeys: String, CodingKey {
        case startedDateTime
        case time
        case pageref
        case id = "_id"
        case app = "_app"
        case request
        case response
        case cache
        case timings
        case serverIPAddress
    }

    static func make(request: ProxyRequest, response: ProxyResponse?) -> ReportHarEntry {
        let started = Self.iso8601UTC(request.timestamp)
        let timeMs: Int = {
            guard let response else { return -1 }
            return max(-1, Int(response.timestamp.timeIntervalSince(request.timestamp) * 1000))
        }()

        return ReportHarEntry(
            startedDateTime: started,
            time: timeMs,
            pageref: "ProxyCore",
            id: request.id,
            app: request.processInfo,
            request: ReportHarRequest.from(request: request),
            response: ReportHarResponse.from(response: response, requestHTTPVersion: request.httpVersion),
            cache: [:],
            timings: ReportHarTimings(send: 0, wait: timeMs, receive: 0),
            serverIPAddress: request.serverIP ?? ""
        )
    }

    private static func iso8601UTC(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: date)
    }
}

struct ReportHarTimings: Codable, Sendable {
    var send: Int
    var wait: Int
    var receive: Int
}

struct ReportHarNameValue: Codable, Sendable {
    var name: String
    var value: String
}

struct ReportHarRequest: Codable, Sendable {
    var method: String
    var url: String
    var httpVersion: String
    var cookies: [String]
    var headers: [ReportHarNameValue]
    var queryString: [ReportHarNameValue]
    var postData: ReportHarPostData?
    var headersSize: Int
    var bodySize: Int

    static func from(request: ProxyRequest) -> ReportHarRequest {
        let headers = request.headers.map { ReportHarNameValue(name: $0.key, value: $0.value) }
        let qs = Self.queryString(from: request.url)
        let postData = Self.postData(from: request)

        let bodySize = request.rawBodySize ?? request.bodyPreview?.count ?? -1

        return ReportHarRequest(
            method: request.method,
            url: request.url,
            httpVersion: request.httpVersion.rawValue,
            cookies: [],
            headers: headers,
            queryString: qs,
            postData: postData,
            headersSize: -1,
            bodySize: bodySize
        )
    }

    private static func queryString(from urlString: String) -> [ReportHarNameValue] {
        guard let url = URL(string: urlString),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return []
        }

        return (comps.queryItems ?? []).map { ReportHarNameValue(name: $0.name, value: $0.value ?? "") }
    }

    private static func postData(from request: ProxyRequest) -> ReportHarPostData? {
        guard let data = request.bodyPreview, !data.isEmpty else { return nil }
        let mime = request.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
        return ReportHarPostData(mimeType: mime, text: Self.bodyText(data))
    }

    private static func bodyText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return data.base64EncodedString()
    }
}

struct ReportHarPostData: Codable, Sendable {
    var mimeType: String
    var text: String?
}

struct ReportHarResponse: Codable, Sendable {
    var status: Int
    var statusText: String
    var httpVersion: String
    var cookies: [String]
    var headers: [ReportHarNameValue]
    var content: ReportHarContent
    var redirectURL: String
    var headersSize: Int
    var bodySize: Int

    static func from(response: ProxyResponse?, requestHTTPVersion: ProxyHTTPVersion) -> ReportHarResponse {
        let status = response?.statusCode ?? 0
        let headers = (response?.headers ?? [:]).map { ReportHarNameValue(name: $0.key, value: $0.value) }
        let body = response?.bodyPreview ?? Data()
        let mime = (response?.headers ?? [:]).first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""

        let bodySize = response?.rawBodySize ?? (body.isEmpty ? -1 : body.count)

        return ReportHarResponse(
            status: status,
            statusText: "",
            httpVersion: response?.httpVersion.rawValue ?? requestHTTPVersion.rawValue,
            cookies: [],
            headers: headers,
            content: ReportHarContent(
                size: body.isEmpty ? -1 : body.count,
                mimeType: Self.normalizeContentType(mime),
                text: body.isEmpty ? "" : Self.bodyText(body)
            ),
            redirectURL: "",
            headersSize: -1,
            bodySize: bodySize
        )
    }

    private static func normalizeContentType(_ type: String) -> String {
        // Match ProxyPin behavior: strip charset.
        let lower = type
        if let r = lower.range(of: "charset=", options: [.caseInsensitive]) {
            var trimmed = String(lower[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(";") { trimmed.removeLast() }
            return trimmed
        }
        return type
    }

    private static func bodyText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return data.base64EncodedString()
    }
}

struct ReportHarContent: Codable, Sendable {
    var size: Int
    var mimeType: String
    var text: String
}

