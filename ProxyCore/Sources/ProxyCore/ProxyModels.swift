import Foundation

public enum ProxyHTTPVersion: String, Sendable, Codable, Hashable {
    case http1_1 = "HTTP/1.1"
    case h2 = "HTTP/2"
}

public struct ProxyClientInfo: Codable, Sendable, Hashable {
    public var ip: String
    public var port: Int?

    public init(ip: String, port: Int?) {
        self.ip = ip
        self.port = port
    }
}

public struct ProxyProcessInfo: Codable, Sendable {
    public var id: String
    public var name: String
    public var path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct ProxyRequest: Sendable {
    public var id: String
    public var timestamp: Date

    public var httpVersion: ProxyHTTPVersion
    public var streamID: Int?

    public var method: String
    public var url: String
    public var headers: [String: String]

    public var bodyPreview: Data?
    public var bodyIsTruncated: Bool
    public var rawBodySize: Int?

    public var client: ProxyClientInfo?
    public var serverIP: String?

    public var processInfo: ProxyProcessInfo?

    public init(
        id: String,
        timestamp: Date = Date(),
        httpVersion: ProxyHTTPVersion,
        streamID: Int? = nil,
        method: String,
        url: String,
        headers: [String: String] = [:],
        bodyPreview: Data? = nil,
        bodyIsTruncated: Bool = false,
        rawBodySize: Int? = nil,
        client: ProxyClientInfo? = nil,
        serverIP: String? = nil,
        processInfo: ProxyProcessInfo? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.httpVersion = httpVersion
        self.streamID = streamID
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyPreview = bodyPreview
        self.bodyIsTruncated = bodyIsTruncated
        self.rawBodySize = rawBodySize
        self.client = client
        self.serverIP = serverIP
        self.processInfo = processInfo
    }
}

public struct ProxyResponse: Sendable {
    public var requestID: String
    public var timestamp: Date

    public var httpVersion: ProxyHTTPVersion
    public var streamID: Int?

    public var statusCode: Int
    public var headers: [String: String]

    public var bodyPreview: Data?
    public var bodyIsTruncated: Bool
    public var rawBodySize: Int?

    public init(
        requestID: String,
        timestamp: Date = Date(),
        httpVersion: ProxyHTTPVersion,
        streamID: Int? = nil,
        statusCode: Int,
        headers: [String: String] = [:],
        bodyPreview: Data? = nil,
        bodyIsTruncated: Bool = false,
        rawBodySize: Int? = nil
    ) {
        self.requestID = requestID
        self.timestamp = timestamp
        self.httpVersion = httpVersion
        self.streamID = streamID
        self.statusCode = statusCode
        self.headers = headers
        self.bodyPreview = bodyPreview
        self.bodyIsTruncated = bodyIsTruncated
        self.rawBodySize = rawBodySize
    }
}
