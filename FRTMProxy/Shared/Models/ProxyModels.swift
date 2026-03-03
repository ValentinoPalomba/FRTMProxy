
import Foundation

// MARK: - WebSocket

enum WebSocketDirection: String, Codable, Equatable { case client, server }
enum WebSocketMessageType: String, Codable, Equatable { case text, binary }

struct WebSocketMessage: Codable, Identifiable, Equatable {
    let id: String
    let direction: WebSocketDirection
    let type: WebSocketMessageType
    let content: String
    let timestamp: TimeInterval
}

/// Transient wrapper used only for decoding a websocket_message bridge event.
struct WebSocketMessageEvent: Codable {
    let event: String
    let id: String
    let timestamp: TimeInterval
    let websocketMessage: WebSocketMessage

    enum CodingKeys: String, CodingKey {
        case event, id, timestamp
        case websocketMessage = "websocket_message"
    }
}

// MARK: - MitmFlow

struct MitmFlow: Identifiable, Codable, Equatable {
    let id: String
    var request: Request?
    var response: Response?
    var event: String
    var timestamp: TimeInterval?
    var requestTimestamp: TimeInterval?
    var responseTimestamp: TimeInterval?
    var client: Client?
    var clientApp: FlowClientApp?
    var breakpoint: FlowBreakpointMetadata?
    var websocketMessages: [WebSocketMessage] = []

    // MARK: Codable — websocketMessages is transient (never decoded from JSON)

    enum CodingKeys: String, CodingKey {
        case id, request, response, event, timestamp
        case requestTimestamp, responseTimestamp
        case client, clientApp, breakpoint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        request = try c.decodeIfPresent(Request.self, forKey: .request)
        response = try c.decodeIfPresent(Response.self, forKey: .response)
        event = try c.decode(String.self, forKey: .event)
        timestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
        requestTimestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .requestTimestamp)
        responseTimestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .responseTimestamp)
        client = try c.decodeIfPresent(Client.self, forKey: .client)
        clientApp = try c.decodeIfPresent(FlowClientApp.self, forKey: .clientApp)
        breakpoint = try c.decodeIfPresent(FlowBreakpointMetadata.self, forKey: .breakpoint)
        websocketMessages = []
    }

    struct Client: Codable, Equatable {
        let ip: String
        let port: Int?
    }

    struct Request: Codable, Equatable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: String?
    }

    struct Response: Codable, Equatable {
        let status: Int?
        let headers: [String: String]?
        let body: String?
    }
}

struct MapRuleRequest: Hashable, Codable, Sendable {
    var method: String
    var url: String
    var headers: [String: String]
    var body: String?

    init(method: String, url: String, headers: [String: String] = [:], body: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

struct MapRule: Identifiable, Hashable, Codable, Sendable {
    let key: String
    let host: String
    let path: String
    var scheme: String?
    var request: MapRuleRequest? = nil
    var body: String
    var status: Int
    var headers: [String: String]
    var isEnabled: Bool = true
    var id: String { key }

    var displayURL: String {
        let scheme = (scheme?.isEmpty ?? true) ? "https" : (scheme ?? "https")
        return "\(scheme)://\(host)\(path)"
    }
}

struct FlowBreakpointMetadata: Codable, Equatable {
    let phase: FlowBreakpointPhase
    let state: FlowBreakpointState
    let key: String
}

enum FlowBreakpointPhase: String, Codable, CaseIterable {
    case request
    case response
}

enum FlowBreakpointState: String, Codable {
    case waiting
    case released
}

struct FlowBreakpointRule: Identifiable, Codable, Hashable {
    let key: String
    let host: String
    let path: String
    var scheme: String?
    var interceptRequest: Bool
    var interceptResponse: Bool
    var isEnabled: Bool

    var id: String { key }

    init(
        key: String,
        host: String,
        path: String,
        scheme: String?,
        interceptRequest: Bool,
        interceptResponse: Bool,
        isEnabled: Bool = true
    ) {
        self.key = key
        self.host = host
        self.path = path
        self.scheme = scheme
        self.interceptRequest = interceptRequest
        self.interceptResponse = interceptResponse
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case key, host, path, scheme, interceptRequest, interceptResponse, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        host = try container.decode(String.self, forKey: .host)
        path = try container.decode(String.self, forKey: .path)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        interceptRequest = try container.decode(Bool.self, forKey: .interceptRequest)
        interceptResponse = try container.decode(Bool.self, forKey: .interceptResponse)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(host, forKey: .host)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(scheme, forKey: .scheme)
        try container.encode(interceptRequest, forKey: .interceptRequest)
        try container.encode(interceptResponse, forKey: .interceptResponse)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    var displayURL: String {
        let scheme = (scheme?.isEmpty ?? true) ? "https" : (scheme ?? "https")
        let normalizedPath = path.isEmpty ? "/" : path
        return "\(scheme)://\(host)\(normalizedPath)"
    }
}

struct BreakpointRequestPayload: Codable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?
}

struct BreakpointResponsePayload: Codable {
    let status: Int
    let headers: [String: String]
    let body: String
}

struct FlowBreakpointHit: Identifiable, Equatable {
    let flowID: String
    let phase: FlowBreakpointPhase
    let key: String
    let timestamp: TimeInterval?

    var id: String {
        "\(flowID)-\(phase.rawValue)"
    }
}
