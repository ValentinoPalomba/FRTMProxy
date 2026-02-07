import Foundation

public actor RequestBlockStore {
    public enum BlockType: String, Codable, Sendable {
        case blockRequest
        case blockResponse
    }

    public struct RequestBlockItem: Codable, Sendable, Hashable {
        public var enabled: Bool
        public var url: String
        public var type: BlockType

        public init(enabled: Bool = true, url: String, type: BlockType) {
            self.enabled = enabled
            self.url = url
            self.type = type
        }
    }

    private struct ConfigFile: Codable {
        var enabled: Bool
        var list: [RequestBlockItem]
    }

    public let fileURL: URL
    public private(set) var enabled: Bool = true
    private var items: [RequestBlockItem] = []
    private var compiled: [String: NSRegularExpression] = [:]

    public init(baseDirectory: URL) {
        self.fileURL = baseDirectory.appending(path: "request_block.json", directoryHint: .notDirectory)
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            enabled = true
            items = []
            compiled = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            enabled = true
            items = []
            compiled = [:]
            return
        }

        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        enabled = decoded.enabled
        items = decoded.list
        compiled = [:]
    }

    public func save() async throws {
        let cfg = ConfigFile(enabled: enabled, list: items)
        let data = try JSONEncoder().encode(cfg)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func isBlocked(url: String, type: BlockType) -> Bool {
        guard enabled else { return false }
        for item in items where item.enabled && item.type == type {
            if matches(url: url, pattern: item.url) {
                return true
            }
        }
        return false
    }

    private func matches(url: String, pattern: String) -> Bool {
        if compiled[pattern] == nil {
            let regexPattern = pattern.replacingOccurrences(of: "*", with: ".*")
            compiled[pattern] = try? NSRegularExpression(pattern: regexPattern, options: [])
        }
        guard let regex = compiled[pattern] else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }
}

