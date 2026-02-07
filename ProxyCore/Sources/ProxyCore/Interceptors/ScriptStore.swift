import Foundation

public struct ScriptEnvironment: Sendable {
    public var deviceID: String?

    public init(deviceID: String? = nil) {
        self.deviceID = deviceID
    }
}

public actor ScriptStore {
    public struct ScriptItem: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var name: String?

        /// URL match patterns. ProxyPin stores this as either a single string (possibly comma-separated) or a list.
        public var urls: [String]

        /// Local script path (ProxyPin-style, often starts with "/scripts/...").
        public var scriptPath: String?

        /// Remote script URL (http/https).
        public var remoteUrl: String?

        public init(
            enabled: Bool = true,
            name: String? = nil,
            urls: [String],
            scriptPath: String? = nil,
            remoteUrl: String? = nil
        ) {
            self.enabled = enabled
            self.name = name
            self.urls = urls
            self.scriptPath = scriptPath
            self.remoteUrl = remoteUrl
        }

        public func matches(url: String, compiled: inout [String: NSRegularExpression]) -> Bool {
            for pattern in urls {
                if Self.matches(url: url, pattern: pattern, compiled: &compiled) {
                    return true
                }
            }
            return false
        }

        private static func matches(url: String, pattern: String, compiled: inout [String: NSRegularExpression]) -> Bool {
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

        // MARK: - Codable (ProxyPin compatibility)

        private enum CodingKeys: String, CodingKey {
            case enabled
            case name
            case url
            case scriptPath
            case remoteUrl
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
            name = try? c.decode(String.self, forKey: .name)
            scriptPath = try? c.decode(String.self, forKey: .scriptPath)
            remoteUrl = try? c.decode(String.self, forKey: .remoteUrl)

            if let list = try? c.decode([String].self, forKey: .url) {
                urls = list
            } else if let single = try? c.decode(String.self, forKey: .url) {
                if single.contains(",") {
                    urls = single.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                } else {
                    urls = [single]
                }
            } else {
                urls = []
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(enabled, forKey: .enabled)
            try c.encodeIfPresent(name, forKey: .name)
            try c.encodeIfPresent(scriptPath, forKey: .scriptPath)
            try c.encodeIfPresent(remoteUrl, forKey: .remoteUrl)

            if urls.count == 1 {
                try c.encode(urls[0], forKey: .url)
            } else {
                try c.encode(urls, forKey: .url)
            }
        }
    }

    private struct ConfigFile: Codable {
        var enabled: Bool
        var list: [ScriptItem]
    }

    private struct CacheEntry {
        var createdAt: Date
        var script: String
    }

    public let fileURL: URL
    public let baseDirectory: URL
    public let environment: ScriptEnvironment

    public private(set) var enabled: Bool = true
    private var list: [ScriptItem] = []

    private var compiled: [String: NSRegularExpression] = [:] // pattern -> regex
    private var scriptCache: [String: CacheEntry] = [:] // key -> cached script

    private let cacheTTL: TimeInterval = 60 * 15

    // ProxyPin-style global script session.
    private var scriptSession: JSONValue = .object([:])

    // Best-effort per-request scriptContext (used by onResponse).
    private var requestContexts: [String: JSONValue] = [:]

    public init(baseDirectory: URL, environment: ScriptEnvironment = ScriptEnvironment()) {
        self.baseDirectory = baseDirectory
        self.fileURL = baseDirectory.appending(path: "script.json", directoryHint: .notDirectory)
        self.environment = environment
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            enabled = true
            list = []
            compiled = [:]
            scriptCache = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            enabled = true
            list = []
            compiled = [:]
            scriptCache = [:]
            return
        }

        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        enabled = decoded.enabled
        list = decoded.list
        compiled = [:]
        scriptCache = [:]
    }

    public func save() async throws {
        let cfg = ConfigFile(enabled: enabled, list: list)
        let data = try JSONEncoder().encode(cfg)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func matchingScripts(url: String) -> [ScriptItem] {
        guard enabled else { return [] }
        return list.filter { $0.enabled && $0.matches(url: url, compiled: &compiled) }
    }

    public func scriptContext(for item: ScriptItem, fallbackName: String? = nil) -> JSONValue {
        var obj: [String: JSONValue] = [
            "scriptName": .string(item.name ?? fallbackName ?? ""),
            "os": .string(Self.osName()),
            "session": scriptSession,
        ]
        if let deviceID = environment.deviceID, !deviceID.isEmpty {
            obj["deviceId"] = .string(deviceID)
        }
        return .object(obj)
    }

    public func contextForRequestID(_ requestID: String) -> JSONValue? {
        requestContexts[requestID]
    }

    public func storeContextForRequestID(_ requestID: String, context: JSONValue) {
        requestContexts[requestID] = context
        // Best-effort: cap growth.
        if requestContexts.count > 10_000 {
            requestContexts.removeAll(keepingCapacity: true)
        }
    }

    public func clearContextForRequestID(_ requestID: String) {
        requestContexts.removeValue(forKey: requestID)
    }

    public func updateSession(fromReturnedObject result: JSONValue) {
        guard
            case .object(let root) = result,
            case .object(let ctx) = root["scriptContext"],
            let sess = ctx["session"]
        else {
            return
        }
        scriptSession = sess
    }

    public func getScript(for item: ScriptItem) async -> String? {
        let key: String? = {
            if let remote = item.remoteUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty {
                return "remote:" + remote
            }
            if let local = item.scriptPath?.trimmingCharacters(in: .whitespacesAndNewlines), !local.isEmpty {
                return "local:" + local
            }
            return nil
        }()

        guard let key else { return nil }

        if let cached = scriptCache[key], Date().timeIntervalSince(cached.createdAt) < cacheTTL {
            return cached.script
        }

        if key.hasPrefix("remote:"), let remote = item.remoteUrl?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard let url = URL(string: remote), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return nil
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let script = String(decoding: data, as: UTF8.self)
                scriptCache[key] = CacheEntry(createdAt: Date(), script: script)
                return script
            } catch {
                return nil
            }
        }

        if let local = item.scriptPath?.trimmingCharacters(in: .whitespacesAndNewlines), !local.isEmpty {
            let url = resolveRelativeURL(local, under: baseDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            scriptCache[key] = CacheEntry(createdAt: Date(), script: script)
            return script
        }

        return nil
    }

    private static func osName() -> String {
        #if os(macOS)
        return "macos"
        #elseif os(iOS)
        return "ios"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }
}

