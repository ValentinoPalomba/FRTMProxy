import Foundation

public actor RequestRewriteStore {
    public enum RuleType: String, Codable, Sendable {
        case requestReplace
        case responseReplace
        case requestUpdate
        case responseUpdate
        case redirect
    }

    public struct RequestRewriteRule: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var type: RuleType
        public var name: String?
        public var url: String
        public var rewritePath: String?
        public var method: String?

        public init(
            enabled: Bool = true,
            type: RuleType,
            name: String? = nil,
            url: String,
            rewritePath: String? = nil,
            method: String? = nil
        ) {
            self.enabled = enabled
            self.type = type
            self.name = name
            self.url = url
            self.rewritePath = rewritePath
            self.method = method
        }
    }

    public enum RewriteType: String, Codable, Sendable {
        case redirect

        case replaceRequestLine
        case replaceRequestHeader
        case replaceRequestBody
        case replaceResponseStatus
        case replaceResponseHeader
        case replaceResponseBody

        case updateBody
        case addQueryParam
        case removeQueryParam
        case updateQueryParam
        case addHeader
        case removeHeader
        case updateHeader
    }

    public struct RewriteItem: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var type: RewriteType
        public var values: [String: JSONValue]

        public init(enabled: Bool, type: RewriteType, values: [String: JSONValue] = [:]) {
            self.enabled = enabled
            self.type = type
            self.values = values
        }

        public var key: String? { values["key"]?.stringValue }
        public var value: String? { values["value"]?.stringValue }

        public var redirectUrl: String? { values["redirectUrl"]?.stringValue }

        public var method: String? { values["method"]?.stringValue }
        public var path: String? { values["path"]?.stringValue }
        public var queryParam: String? { values["queryParam"]?.stringValue }
        public var statusCode: Int? { values["statusCode"]?.intValue }
        public var headers: [String: String]? {
            guard let obj = values["headers"]?.objectValue else { return nil }
            var out: [String: String] = [:]
            for (k, v) in obj {
                if let s = v.stringValue {
                    out[k] = s
                }
            }
            return out
        }

        public var body: String? { values["body"]?.stringValue }
        public var bodyType: String? { values["bodyType"]?.stringValue }
        public var bodyFile: String? { values["bodyFile"]?.stringValue }
    }

    public struct Match: Sendable {
        public var rule: RequestRewriteRule
        public var items: [RewriteItem]
    }

    private struct ConfigFile: Codable {
        var enabled: Bool
        var rules: [RequestRewriteRule]
    }

    public let fileURL: URL
    public let baseDirectory: URL

    public private(set) var enabled: Bool = true
    private var rules: [RequestRewriteRule] = []

    private var compiled: [String: NSRegularExpression] = [:]
    private var itemsCache: [String: [RewriteItem]] = [:] // rewritePath -> items

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        self.fileURL = baseDirectory.appending(path: "request_rewrite.json", directoryHint: .notDirectory)
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            enabled = true
            rules = []
            compiled = [:]
            itemsCache = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            enabled = true
            rules = []
            compiled = [:]
            itemsCache = [:]
            return
        }

        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        enabled = decoded.enabled
        rules = decoded.rules
        compiled = [:]
        itemsCache = [:]
    }

    public func save() async throws {
        let cfg = ConfigFile(enabled: enabled, rules: rules)
        let data = try JSONEncoder().encode(cfg)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func match(url: String, method: String?, allowedTypes: [RuleType]) async -> Match? {
        guard enabled else { return nil }
        let types = Set(allowedTypes)

        for rule in rules where rule.enabled && types.contains(rule.type) {
            if let method, let ruleMethod = rule.method, !ruleMethod.isEmpty {
                if ruleMethod.uppercased() != method.uppercased() {
                    continue
                }
            }
            if matches(url: url, pattern: rule.url) {
                let items = await loadItemsIfNeeded(for: rule.rewritePath) ?? []
                return Match(rule: rule, items: items)
            }
        }

        return nil
    }

    public func resolveRedirect(url: String) async -> String? {
        guard let match = await match(url: url, method: nil, allowedTypes: [.redirect]) else { return nil }
        guard let enabledItem = match.items.first(where: { $0.enabled }), var redirect = enabledItem.redirectUrl else {
            return nil
        }

        // ProxyPin wildcard substitution.
        if match.rule.url.contains("*"), redirect.contains("*") {
            let ruleNoStar = match.rule.url.replacingOccurrences(of: "*", with: "")
            let remainder = url.replacingOccurrences(of: ruleNoStar, with: "")
            redirect = redirect.replacingOccurrences(of: "*", with: remainder)
        }
        return redirect
    }

    private func matches(url: String, pattern: String) -> Bool {
        if compiled[pattern] == nil {
            let regexPattern = pattern
                .replacingOccurrences(of: "*", with: ".*")
                .replacingOccurrences(of: "?", with: "\\?")
            compiled[pattern] = try? NSRegularExpression(pattern: regexPattern, options: [])
        }
        guard let regex = compiled[pattern] else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    private func loadItemsIfNeeded(for rewritePath: String?) async -> [RewriteItem]? {
        guard let rewritePath, !rewritePath.isEmpty else { return nil }
        if let cached = itemsCache[rewritePath] {
            return cached
        }

        let url = resolveRelativeURL(rewritePath, under: baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return nil }
            let items = try JSONDecoder().decode([RewriteItem].self, from: data)
            itemsCache[rewritePath] = items
            return items
        } catch {
            return nil
        }
    }
}

