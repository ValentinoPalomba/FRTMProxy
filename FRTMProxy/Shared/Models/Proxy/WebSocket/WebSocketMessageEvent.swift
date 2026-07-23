import Foundation

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
