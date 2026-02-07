import Foundation

public enum ProxyEvent: Sendable {
    case request(ProxyRequest)
    case response(ProxyResponse)
    case webSocketMessage(ProxyWebSocketMessage)
    case sseEvent(ProxySSEEvent)
    case error(ProxyErrorEvent)
    case log(String)
}

public struct ProxyErrorEvent: Sendable {
    public var requestID: String?
    public var message: String

    public init(requestID: String?, message: String) {
        self.requestID = requestID
        self.message = message
    }
}

public struct ProxyWebSocketMessage: Sendable {
    public enum Direction: Sendable {
        case clientToServer
        case serverToClient
    }

    public var requestID: String
    public var direction: Direction
    public var isText: Bool
    public var data: Data

    public init(requestID: String, direction: Direction, isText: Bool, data: Data) {
        self.requestID = requestID
        self.direction = direction
        self.isText = isText
        self.data = data
    }
}

public struct ProxySSEEvent: Sendable {
    public var requestID: String
    public var event: String?
    public var id: String?
    public var data: String

    public init(requestID: String, event: String?, id: String?, data: String) {
        self.requestID = requestID
        self.event = event
        self.id = id
        self.data = data
    }
}
