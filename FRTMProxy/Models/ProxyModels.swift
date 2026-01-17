
import Foundation
import CoreData

@objc(CDFlow)
public class CDFlow: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var timestamp: Double
    @NSManaged public var clientIP: String?
    @NSManaged public var requestMethod: String?
    @NSManaged public var requestURL: String?
    @NSManaged public var requestHeaders: Data?
    @NSManaged public var requestBody: String?
    @NSManaged public var responseStatus: Int32
    @NSManaged public var responseHeaders: Data?
    @NSManaged public var responseBody: String?
    @NSManaged public var breakpointPhase: String?
    @NSManaged public var breakpointState: String?
    @NSManaged public var breakpointKey: String?
}

extension CDFlow: Identifiable {
    static func fetchRequest() -> NSFetchRequest<CDFlow> {
        return NSFetchRequest<CDFlow>(entityName: "CDFlow")
    }
}

struct MitmFlow: Identifiable, Codable, Equatable {
    let id: String
    var request: Request?
    var response: Response?
    var event: String
    var timestamp: TimeInterval?
    var client: Client?
    var breakpoint: FlowBreakpointMetadata?
    
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

    @discardableResult
    func populate(cd: CDFlow) -> CDFlow {
        cd.id = self.id
        cd.timestamp = self.timestamp ?? 0
        cd.clientIP = self.client?.ip

        if let request = self.request {
            cd.requestMethod = request.method
            cd.requestURL = request.url
            cd.requestBody = request.body
            cd.requestHeaders = try? JSONEncoder().encode(request.headers)
        }

        if let response = self.response {
            cd.responseStatus = Int32(response.status ?? 0)
            cd.responseBody = response.body
            cd.responseHeaders = try? JSONEncoder().encode(response.headers)
        }

        if let breakpoint = self.breakpoint {
            cd.breakpointPhase = breakpoint.phase.rawValue
            cd.breakpointState = breakpoint.state.rawValue
            cd.breakpointKey = breakpoint.key
        }

        return cd
    }
}

struct MapRule: Identifiable, Hashable, Codable {
    let key: String
    let host: String
    let path: String
    var scheme: String?
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
