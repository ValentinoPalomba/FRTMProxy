import Foundation

struct FlowBreakpointRule: Identifiable, Codable, Hashable {
    let key: String
    let host: String
    let path: String
    var scheme: String?
    var method: String? // nil matches every HTTP method
    var interceptRequest: Bool
    var interceptResponse: Bool
    var isEnabled: Bool

    var id: String { key }

    static func normalizedMethod(_ raw: String?) -> String? {
        guard let method = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !method.isEmpty else { return nil }
        return method
    }

    static func key(host: String, path: String, method: String?) -> String {
        let base = host + path
        guard let method = normalizedMethod(method) else { return base }
        return "\(base)#method=\(method)"
    }

    init(
        key: String,
        host: String,
        path: String,
        scheme: String?,
        interceptRequest: Bool,
        interceptResponse: Bool,
        isEnabled: Bool = true,
        method: String? = nil
    ) {
        self.key = key
        self.host = host
        self.path = path
        self.scheme = scheme
        self.method = Self.normalizedMethod(method)
        self.interceptRequest = interceptRequest
        self.interceptResponse = interceptResponse
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case key, host, path, scheme, method, interceptRequest, interceptResponse, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        host = try container.decode(String.self, forKey: .host)
        path = try container.decode(String.self, forKey: .path)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        method = Self.normalizedMethod(try container.decodeIfPresent(String.self, forKey: .method))
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
        try container.encodeIfPresent(method, forKey: .method)
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
