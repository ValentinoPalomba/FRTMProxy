import Foundation

public actor RequestMapStore {
    public enum RequestMapType: String, Codable, Sendable {
        case local
        case script
    }

    public struct RequestMapRule: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var type: RequestMapType
        public var name: String?
        public var url: String
        public var itemPath: String?

        public init(enabled: Bool = true, type: RequestMapType, name: String? = nil, url: String, itemPath: String? = nil) {
            self.enabled = enabled
            self.type = type
            self.name = name
            self.url = url
            self.itemPath = itemPath
        }
    }

    public struct RequestMapItem: Codable, Sendable, Hashable {
        public var script: String?
        public var statusCode: Int?
        public var headers: [String: String]?

        public var body: String?
        public var bodyType: String?
        public var bodyFile: String?

        public init(
            script: String? = nil,
            statusCode: Int? = nil,
            headers: [String: String]? = nil,
            body: String? = nil,
            bodyType: String? = nil,
            bodyFile: String? = nil
        ) {
            self.script = script
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.bodyType = bodyType
            self.bodyFile = bodyFile
        }
    }

    public struct Match: Sendable {
        public var rule: RequestMapRule
        public var item: RequestMapItem?
    }

    private struct ConfigFile: Codable {
        var enabled: Bool
        var list: [RequestMapRule]
    }

    public let fileURL: URL
    public let baseDirectory: URL

    public private(set) var enabled: Bool = true
    private var rules: [RequestMapRule] = []

    private var compiled: [String: NSRegularExpression] = [:]
    private var itemCache: [String: RequestMapItem] = [:]

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        self.fileURL = baseDirectory.appending(path: "request_map.json", directoryHint: .notDirectory)
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            enabled = true
            rules = []
            compiled = [:]
            itemCache = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            enabled = true
            rules = []
            compiled = [:]
            itemCache = [:]
            return
        }

        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        enabled = decoded.enabled
        rules = decoded.list
        compiled = [:]
        itemCache = [:]
    }

    public func save() async throws {
        let cfg = ConfigFile(enabled: enabled, list: rules)
        let data = try JSONEncoder().encode(cfg)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func findMatch(url: String) async -> Match? {
        guard enabled else { return nil }
        for rule in rules where rule.enabled {
            if matches(url: url, pattern: rule.url) {
                let item = await loadItemIfNeeded(for: rule.itemPath)
                return Match(rule: rule, item: item)
            }
        }
        return nil
    }

    private func matches(url: String, pattern: String) -> Bool {
        if compiled[pattern] == nil {
            // ProxyPin semantics: `* -> .*` and escape '?' (best-effort).
            let regexPattern = pattern
                .replacingOccurrences(of: "*", with: ".*")
                .replacingOccurrences(of: "?", with: "\\?")
            compiled[pattern] = try? NSRegularExpression(pattern: regexPattern, options: [])
        }
        guard let regex = compiled[pattern] else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    private func loadItemIfNeeded(for itemPath: String?) async -> RequestMapItem? {
        guard let itemPath, !itemPath.isEmpty else { return nil }
        if let cached = itemCache[itemPath] {
            return cached
        }

        let url = resolveRelativeURL(itemPath, under: baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return nil }
            let item = try JSONDecoder().decode(RequestMapItem.self, from: data)
            itemCache[itemPath] = item
            return item
        } catch {
            return nil
        }
    }
}

func resolveRelativeURL(_ path: String, under base: URL) -> URL {
    // ProxyPin stores paths starting with a separator (e.g. "/request_map/abc.json").
    let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    return base.appending(path: trimmed)
}
