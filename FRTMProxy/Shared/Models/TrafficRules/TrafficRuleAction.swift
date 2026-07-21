import Foundation

enum TrafficRuleAction: Codable, Hashable, Sendable, Identifiable {
    struct Mock: Codable, Hashable, Sendable { let id: UUID; var status: Int; var headers: [String: String]; var body: String }
    struct MapRemote: Codable, Hashable, Sendable { let id: UUID; var destinationURL: String; var preservePath: Bool; var preserveQuery: Bool }
    struct RewriteRequest: Codable, Hashable, Sendable { let id: UUID; var method: String?; var url: String?; var headers: [String: String]; var body: String? }
    struct RewriteResponse: Codable, Hashable, Sendable { let id: UUID; var status: Int?; var headers: [String: String]; var body: String? }
    struct Block: Codable, Hashable, Sendable { let id: UUID; var status: Int; var headers: [String: String]; var body: String }
    struct Delay: Codable, Hashable, Sendable { let id: UUID; var requestMilliseconds: Int; var responseMilliseconds: Int }
    struct Breakpoint: Codable, Hashable, Sendable { let id: UUID; var request: Bool; var response: Bool }
    struct Script: Codable, Hashable, Sendable { let id: UUID; var source: String; var responseOnly: Bool }

    case mock(Mock)
    case mapRemote(MapRemote)
    case rewriteRequest(RewriteRequest)
    case rewriteResponse(RewriteResponse)
    case block(Block)
    case delay(Delay)
    case breakpoint(Breakpoint)
    case script(Script)

    var id: UUID {
        switch self {
        case .mock(let value): value.id
        case .mapRemote(let value): value.id
        case .rewriteRequest(let value): value.id
        case .rewriteResponse(let value): value.id
        case .block(let value): value.id
        case .delay(let value): value.id
        case .breakpoint(let value): value.id
        case .script(let value): value.id
        }
    }

    private enum CodingKeys: String, CodingKey { case type, configuration }
    private enum Kind: String, Codable { case mock, mapRemote, rewriteRequest, rewriteResponse, block, delay, breakpoint, script }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .mock: self = .mock(try container.decode(Mock.self, forKey: .configuration))
        case .mapRemote: self = .mapRemote(try container.decode(MapRemote.self, forKey: .configuration))
        case .rewriteRequest: self = .rewriteRequest(try container.decode(RewriteRequest.self, forKey: .configuration))
        case .rewriteResponse: self = .rewriteResponse(try container.decode(RewriteResponse.self, forKey: .configuration))
        case .block: self = .block(try container.decode(Block.self, forKey: .configuration))
        case .delay: self = .delay(try container.decode(Delay.self, forKey: .configuration))
        case .breakpoint: self = .breakpoint(try container.decode(Breakpoint.self, forKey: .configuration))
        case .script: self = .script(try container.decode(Script.self, forKey: .configuration))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mock(let value): try container.encode(Kind.mock, forKey: .type); try container.encode(value, forKey: .configuration)
        case .mapRemote(let value): try container.encode(Kind.mapRemote, forKey: .type); try container.encode(value, forKey: .configuration)
        case .rewriteRequest(let value): try container.encode(Kind.rewriteRequest, forKey: .type); try container.encode(value, forKey: .configuration)
        case .rewriteResponse(let value): try container.encode(Kind.rewriteResponse, forKey: .type); try container.encode(value, forKey: .configuration)
        case .block(let value): try container.encode(Kind.block, forKey: .type); try container.encode(value, forKey: .configuration)
        case .delay(let value): try container.encode(Kind.delay, forKey: .type); try container.encode(value, forKey: .configuration)
        case .breakpoint(let value): try container.encode(Kind.breakpoint, forKey: .type); try container.encode(value, forKey: .configuration)
        case .script(let value): try container.encode(Kind.script, forKey: .type); try container.encode(value, forKey: .configuration)
        }
    }
}
