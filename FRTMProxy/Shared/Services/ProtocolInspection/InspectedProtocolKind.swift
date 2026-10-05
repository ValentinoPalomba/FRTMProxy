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
    case ndjson
    case aiAPI
    case jsonRPC
    case paymentFlow
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
        case .ndjson: "NDJSON"
        case .aiAPI: "AI API"
        case .jsonRPC: "JSON-RPC"
        case .paymentFlow: "Payment flow"
        case .xml: "XML"
        case .html: "HTML"
        case .text: "Text"
        case .binary: "Binary"
        }
    }
}
