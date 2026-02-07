import Foundation

public actor FavoritesStore {
    public enum Error: Swift.Error {
        case failedToRead(URL)
        case failedToWrite(URL)
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL, fileName: String = "favorites.json") {
        self.fileURL = baseDirectory
            .appending(path: "favorites", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func load() throws -> [HistoryFlow] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            if data.isEmpty { return [] }
            return try decoder.decode([HistoryFlow].self, from: data)
        } catch {
            throw Error.failedToRead(fileURL)
        }
    }

    public func save(_ flows: [HistoryFlow]) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(flows)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw Error.failedToWrite(fileURL)
        }
    }

    public func add(_ flow: HistoryFlow) throws {
        var existing = try load()
        existing.removeAll { $0.id == flow.id }
        existing.insert(flow, at: 0)
        try save(existing)
    }

    public func remove(flowID: String) throws {
        let existing = try load().filter { $0.id != flowID }
        try save(existing)
    }
}

