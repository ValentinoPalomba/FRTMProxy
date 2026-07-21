import Foundation

enum InspectedProtocolKind: String, Codable, CaseIterable, Sendable {
    case json
    case graphQL
    case grpc
    case jwt
    case cookies
    case formURLEncoded
    case multipart
    case serverSentEvents
    case xml
    case html
    case text
    case binary

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .graphQL: "GraphQL"
        case .grpc: "gRPC"
        case .jwt: "JWT"
        case .cookies: "Cookies"
        case .formURLEncoded: "Form"
        case .multipart: "Multipart"
        case .serverSentEvents: "SSE"
        case .xml: "XML"
        case .html: "HTML"
        case .text: "Text"
        case .binary: "Binary"
        }
    }
}
