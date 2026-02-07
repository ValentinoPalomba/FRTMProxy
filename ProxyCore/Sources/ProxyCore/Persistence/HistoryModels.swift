import Foundation

public struct HistoryFlow: Codable, Sendable, Hashable {
    public var id: String
    public var startedAt: Date

    public var httpVersion: ProxyHTTPVersion
    public var streamID: Int?

    public var request: HistoryRequest
    public var response: HistoryResponse?

    public var client: ProxyClientInfo?
    public var serverIP: String?

    public init(
        id: String,
        startedAt: Date,
        httpVersion: ProxyHTTPVersion,
        streamID: Int? = nil,
        request: HistoryRequest,
        response: HistoryResponse? = nil,
        client: ProxyClientInfo? = nil,
        serverIP: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.httpVersion = httpVersion
        self.streamID = streamID
        self.request = request
        self.response = response
        self.client = client
        self.serverIP = serverIP
    }
}

public struct HistoryRequest: Codable, Sendable, Hashable {
    public var method: String
    public var url: String
    public var headers: [String: String]

    /// Base64-encoded body preview (may be full body if not truncated).
    public var bodyBase64: String?
    public var bodyIsTruncated: Bool
    public var rawBodySize: Int?

    public init(
        method: String,
        url: String,
        headers: [String: String],
        bodyBase64: String? = nil,
        bodyIsTruncated: Bool,
        rawBodySize: Int? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyBase64 = bodyBase64
        self.bodyIsTruncated = bodyIsTruncated
        self.rawBodySize = rawBodySize
    }
}

public struct HistoryResponse: Codable, Sendable, Hashable {
    public var statusCode: Int
    public var headers: [String: String]

    /// Base64-encoded body preview (may be full body if not truncated).
    public var bodyBase64: String?
    public var bodyIsTruncated: Bool
    public var rawBodySize: Int?

    public init(
        statusCode: Int,
        headers: [String: String],
        bodyBase64: String? = nil,
        bodyIsTruncated: Bool,
        rawBodySize: Int? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.bodyBase64 = bodyBase64
        self.bodyIsTruncated = bodyIsTruncated
        self.rawBodySize = rawBodySize
    }
}

extension HistoryFlow {
    public init(from request: ProxyRequest) {
        self.init(
            id: request.id,
            startedAt: request.timestamp,
            httpVersion: request.httpVersion,
            streamID: request.streamID,
            request: HistoryRequest(
                method: request.method,
                url: request.url,
                headers: request.headers,
                bodyBase64: request.bodyPreview?.base64EncodedString(),
                bodyIsTruncated: request.bodyIsTruncated,
                rawBodySize: request.rawBodySize
            ),
            response: nil,
            client: request.client,
            serverIP: request.serverIP
        )
    }
}

extension HistoryResponse {
    public init(from response: ProxyResponse) {
        self.init(
            statusCode: response.statusCode,
            headers: response.headers,
            bodyBase64: response.bodyPreview?.base64EncodedString(),
            bodyIsTruncated: response.bodyIsTruncated,
            rawBodySize: response.rawBodySize
        )
    }
}

