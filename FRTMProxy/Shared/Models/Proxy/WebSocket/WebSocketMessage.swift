import Foundation

struct WebSocketMessage: Codable, Identifiable, Equatable {
    let id: String
    let direction: WebSocketDirection
    let type: WebSocketMessageType
    let content: String
    let timestamp: TimeInterval
}
