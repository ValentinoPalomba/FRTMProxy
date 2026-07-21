import Foundation

enum LocalMCPServerError: LocalizedError {
    case pathTooLong
    case socketCreation(Int32)
    case bind(Int32)
    case listen(Int32)

    var errorDescription: String? {
        switch self {
        case .pathTooLong: "The MCP Unix socket path is too long."
        case .socketCreation(let code): "Unable to create MCP socket (errno \(code))."
        case .bind(let code): "Unable to bind MCP socket (errno \(code))."
        case .listen(let code): "Unable to listen on MCP socket (errno \(code))."
        }
    }
}
