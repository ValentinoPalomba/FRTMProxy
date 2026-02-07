import Foundation

public actor ReportServerStore {
    public struct ReportServer: Codable, Sendable, Hashable {
        public var name: String
        public var matchUrl: String
        public var serverUrl: String
        public var enabled: Bool
        public var compression: String?

        public init(
            name: String,
            matchUrl: String,
            serverUrl: String,
            enabled: Bool = true,
            compression: String? = "none"
        ) {
            self.name = name
            self.matchUrl = matchUrl
            self.serverUrl = serverUrl
            self.enabled = enabled
            self.compression = compression
        }
    }

    public let fileURL: URL

    private var servers: [ReportServer] = []
    private var compiled: [String: NSRegularExpression] = [:]

    public init(baseDirectory: URL) {
        self.fileURL = baseDirectory.appending(path: "report_servers.json", directoryHint: .notDirectory)
    }

    public func loadIfPresent() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            servers = []
            compiled = [:]
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            servers = []
            compiled = [:]
            return
        }

        servers = try JSONDecoder().decode([ReportServer].self, from: data)
        compiled = [:]
    }

    public func save() async throws {
        let data = try JSONEncoder().encode(servers)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func matchServer(url: String) -> ReportServer? {
        for server in servers {
            guard server.enabled else { continue }
            if matches(url: url, pattern: server.matchUrl) {
                return server
            }
        }
        return nil
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
}

