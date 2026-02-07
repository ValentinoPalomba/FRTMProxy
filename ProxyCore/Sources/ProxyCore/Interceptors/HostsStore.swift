import Foundation

public actor HostsStore {
    public struct HostsItem: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var isFolder: Bool
        public var id: String
        public var parent: String?
        public var host: String
        public var toAddress: String?

        public init(
            enabled: Bool = true,
            isFolder: Bool = false,
            id: String,
            parent: String? = nil,
            host: String,
            toAddress: String? = nil
        ) {
            self.enabled = enabled
            self.isFolder = isFolder
            self.id = id
            self.parent = parent
            self.host = host
            self.toAddress = toAddress
        }
    }

    private struct ConfigFile: Codable {
        var enabled: Bool
        var list: [HostsItem]
    }

    public let fileURL: URL
    public private(set) var enabled: Bool = true

    private var rootItems: [HostsItem] = []
    private var folderChildren: [String: [HostsItem]] = [:]

    // Compiled regex cache keyed by the raw host pattern.
    private var compiled: [String: NSRegularExpression] = [:]

    public init(baseDirectory: URL) {
        self.fileURL = baseDirectory.appending(path: "hosts.json", directoryHint: .notDirectory)
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            enabled = true
            rootItems = []
            folderChildren = [:]
            compiled = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            enabled = true
            rootItems = []
            folderChildren = [:]
            compiled = [:]
            return
        }

        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        enabled = decoded.enabled

        var roots: [HostsItem] = []
        var children: [String: [HostsItem]] = [:]

        for item in decoded.list {
            if let parent = item.parent {
                children[parent, default: []].append(item)
            } else {
                roots.append(item)
                if item.isFolder {
                    children[item.id] = children[item.id] ?? []
                }
            }
        }

        rootItems = roots
        folderChildren = children
        compiled = [:]
    }

    public func save() async throws {
        let all = rootItems + folderChildren.values.flatMap { $0 }
        let cfg = ConfigFile(enabled: enabled, list: all)
        let data = try JSONEncoder().encode(cfg)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Returns the mapped address for a given host, if a rule matches.
    public func resolve(host: String) -> String? {
        guard enabled else { return nil }

        for item in rootItems {
            if !item.enabled { continue }

            if item.isFolder {
                for child in folderChildren[item.id] ?? [] {
                    guard child.enabled else { continue }
                    if matches(host: host, pattern: child.host), let to = child.toAddress, !to.isEmpty {
                        return to
                    }
                }
                continue
            }

            if matches(host: host, pattern: item.host), let to = item.toAddress, !to.isEmpty {
                return to
            }
        }

        return nil
    }

    private func matches(host: String, pattern: String) -> Bool {
        if compiled[pattern] == nil {
            // ProxyPin semantics: pattern string is treated as a regex after `* -> .*`, without escaping.
            let regexPattern = pattern.replacingOccurrences(of: "*", with: ".*")
            compiled[pattern] = try? NSRegularExpression(pattern: regexPattern, options: [])
        }
        guard let regex = compiled[pattern] else { return false }
        let range = NSRange(host.startIndex..<host.endIndex, in: host)
        return regex.firstMatch(in: host, options: [], range: range) != nil
    }
}

