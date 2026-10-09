import CryptoKit
import Foundation
import Darwin

/// Original bytes stay encrypted on disk; the live flow only carries a bounded preview and a filename.
enum CaptureBodyStore {
    static var directory: URL {
        CaptureStorageConfiguration.root.appending(path: "FRTMProxy/Bodies", directoryHint: .isDirectory)
    }

    static func environment() throws -> [String: String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let key = try CaptureStorageConfiguration.keyProvider.loadOrCreateKey()
        return ["FRTMPROXY_BODY_DIRECTORY": directory.path,
                "FRTMPROXY_BODY_KEY": key.withUnsafeBytes { Data($0).base64EncodedString() }]
    }

    static func save(_ body: Data, flowID: String, phase: String, directory: URL, key: SymmetricKey) throws -> String {
        guard ["request", "response"].contains(phase), body.count <= 64 * 1024 * 1024 else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let reference = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + ".gcm"
        let box = try AES.GCM.seal(body, using: key, authenticating: Data("\(flowID):\(phase)".utf8))
        guard let combined = box.combined else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appending(path: reference)
        guard FileManager.default.createFile(atPath: url.path, contents: combined,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return reference
    }

    static func isValidReference(_ reference: String) -> Bool {
        reference.utf8.count == 36 && reference.hasSuffix(".gcm") &&
        reference.dropLast(4).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Only expired unreferenced files are eligible, and never while a bridge is capturing.
    static func pruneOrphans(directory: URL, before cutoff: Date,
                             isReferenced: (String) throws -> Bool) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let descriptor = open(directory.appending(path: ".capture.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { return 0 }
            throw CocoaError(.fileReadUnknown)
        }
        defer { flock(descriptor, LOCK_UN) }
        let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
        var removed = 0
        for url in files where isValidReference(url.lastPathComponent) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < cutoff,
                  try !isReferenced(url.lastPathComponent) else { continue }
            try FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    static func load(reference: String, flowID: String, phase: String,
                     directory: URL = directory,
                     keyProvider: any SessionEncryptionKeyProviding = CaptureStorageConfiguration.keyProvider,
                     maximumBytes: Int = 64 * 1024 * 1024) throws -> Data {
        guard isValidReference(reference),
              ["request", "response"].contains(phase) else { throw CocoaError(.fileReadInvalidFileName) }
        let url = directory.appending(path: reference)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= maximumBytes + 28 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        return try AES.GCM.open(box, using: keyProvider.loadOrCreateKey(),
                                authenticating: Data("\(flowID):\(phase)".utf8))
    }
}
