import CryptoKit
import Foundation

actor ComposerStateStore {
    struct State: Codable, Equatable, Sendable {
        var history: [ComposerDraft] = []
        var variables: [ComposerHeaderRow] = []
    }
    let url: URL
    let keyProvider: any SessionEncryptionKeyProviding
    init(url: URL = URL.applicationSupportDirectory.appending(path: "FRTMProxy/Composer/state.gcm"),
         keyProvider: any SessionEncryptionKeyProviding = KeychainSessionEncryptionKeyProvider()) {
        self.url = url; self.keyProvider = keyProvider
    }
    func load() throws -> State {
        guard FileManager.default.fileExists(atPath: url.path) else { return State() }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 8 * 1024 * 1024 + 28 else { throw CocoaError(.fileReadTooLarge) }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let plaintext = try AES.GCM.open(box, using: keyProvider.loadOrCreateKey(), authenticating: Data("frtm-composer-v1".utf8))
        return try JSONDecoder().decode(State.self, from: plaintext)
    }
    func resetPreservingBackup() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("backup-\(UUID().uuidString)"))
        }
        _ = try save(State())
    }
    @discardableResult
    func save(_ incoming: State) throws -> State {
        var state = incoming
        state.history = Array(state.history.prefix(50))
        var bytes = try JSONEncoder().encode(state)
        while bytes.count > 8 * 1024 * 1024, !state.history.isEmpty {
            state.history.removeLast()
            bytes = try JSONEncoder().encode(state)
        }
        guard bytes.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        let box = try AES.GCM.seal(bytes, using: keyProvider.loadOrCreateKey(), authenticating: Data("frtm-composer-v1".utf8))
        guard let combined = box.combined else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try combined.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return state
    }
}
