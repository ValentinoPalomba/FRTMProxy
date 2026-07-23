import Foundation

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
