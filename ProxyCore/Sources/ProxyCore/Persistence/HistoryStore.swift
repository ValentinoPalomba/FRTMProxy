import Foundation

public enum HistoryStoreError: Error {
    case invalidBaseDirectory
    case failedToCreateDirectory(URL)
    case failedToOpenFile(URL)
}

/// A minimal write-through history store that persists completed request/response pairs as JSON Lines.
///
/// Notes:
/// - Bodies are stored as base64 (preview/full, depending on capture limits).
/// - WebSocket/SSE events are not persisted (yet).
public actor HistoryStore {
    public struct Configuration: Sendable {
        public var retentionDays: Int
        public var fileName: String

        public init(retentionDays: Int = 7, fileName: String = "history.jsonl") {
            self.retentionDays = retentionDays
            self.fileName = fileName
        }
    }

    private let directoryURL: URL
    private let fileURL: URL
    private let config: Configuration

    private var fileHandle: FileHandle?
    private var pending: [String: HistoryFlow] = [:]

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init(baseDirectory: URL, configuration: Configuration = Configuration()) throws {
        self.directoryURL = baseDirectory.appending(path: "history", directoryHint: .isDirectory)
        self.fileURL = directoryURL.appending(path: configuration.fileName, directoryHint: .notDirectory)
        self.config = configuration

        try Self.ensureDirectoryExists(directoryURL)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seekToEnd()
        } catch {
            throw HistoryStoreError.failedToOpenFile(fileURL)
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    public func handle(event: ProxyEvent) async {
        switch event {
        case .request(let req):
            pending[req.id] = HistoryFlow(from: req)
        case .response(let res):
            guard var flow = pending[res.requestID] else { return }
            flow.response = HistoryResponse(from: res)
            pending.removeValue(forKey: res.requestID)
            try? append(flow)
        default:
            return
        }
    }

    public func loadAll() throws -> [HistoryFlow] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return [] }

        var out: [HistoryFlow] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if line.isEmpty { continue }
            do {
                out.append(try decoder.decode(HistoryFlow.self, from: Data(line)))
            } catch {
                // Skip malformed lines for resilience.
                continue
            }
        }
        return out
    }

    public func clear() throws {
        try fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle?.seekToEnd()
        pending.removeAll()
    }

    public func prune() throws {
        guard config.retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-config.retentionDays * 24 * 60 * 60))
        let flows = try loadAll().filter { $0.startedAt >= cutoff }

        try fileHandle?.close()
        fileHandle = nil
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle?.seekToEnd()

        for flow in flows {
            try append(flow)
        }
    }

    // MARK: - Internals

    private func append(_ flow: HistoryFlow) throws {
        guard let fileHandle else { throw HistoryStoreError.failedToOpenFile(fileURL) }
        let json = try encoder.encode(flow)
        var line = Data()
        line.append(json)
        line.append(UInt8(ascii: "\n"))
        try fileHandle.write(contentsOf: line)
    }

    nonisolated private static func ensureDirectoryExists(_ url: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw HistoryStoreError.invalidBaseDirectory
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw HistoryStoreError.failedToCreateDirectory(url)
        }
    }
}

