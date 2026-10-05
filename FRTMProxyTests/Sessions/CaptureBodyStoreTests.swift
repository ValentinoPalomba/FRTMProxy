import CryptoKit
import Foundation
import Darwin
import Testing
@testable import FRTMProxy

@Suite("Encrypted original bodies")
struct CaptureBodyStoreTests {
    private struct KeyProvider: SessionEncryptionKeyProviding {
        func loadOrCreateKey() throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 0, count: 32)) }
    }

    @Test func orphanCollectionPreservesReferencedFreshAndActiveCaptureFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = String(repeating: "a", count: 32) + ".gcm"
        let referenced = String(repeating: "b", count: 32) + ".gcm"
        let recent = String(repeating: "c", count: 32) + ".gcm"
        let link = String(repeating: "d", count: 32) + ".gcm"
        for name in [old, referenced, recent] { try Data("fixture".utf8).write(to: directory.appending(path: name)) }
        for name in [old, referenced] {
            try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-48 * 60 * 60)],
                                                  ofItemAtPath: directory.appending(path: name).path)
        }
        try FileManager.default.createSymbolicLink(at: directory.appending(path: link), withDestinationURL: directory.appending(path: old))
        let descriptor = open(directory.appending(path: ".capture.lock").path, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_SH | LOCK_NB) == 0)
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        #expect(try CaptureBodyStore.pruneOrphans(directory: directory, before: cutoff) { $0 == referenced } == 0)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: old).path))
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(try CaptureBodyStore.pruneOrphans(directory: directory, before: cutoff) { $0 == referenced } == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: referenced).path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: recent).path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: directory.appending(path: link).path) == directory.appending(path: old).path)
    }

    @Test func decryptsPythonAESGCMAndRejectsWrongFlowAndTraversal() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = String(repeating: "a", count: 32) + ".gcm"
        // Python cryptography AESGCM: zero key, nonce 00...0b, AAD test-flow:response.
        let combined = try #require(Data(base64Encoded: "AAECAwQFBgcICQoL57laNWmT7pXiGiuRmHDe88R6MWG+dMxB+Pa0Ne+QJ8M="))
        try combined.write(to: directory.appending(path: reference))
        let bytes = try CaptureBodyStore.load(reference: reference, flowID: "test-flow", phase: "response",
                                             directory: directory, keyProvider: KeyProvider())
        #expect(bytes == Data("original bytes".utf8) + Data([0, 255]))
        #expect(throws: (any Error).self) {
            try CaptureBodyStore.load(reference: reference, flowID: "wrong-flow", phase: "response",
                                      directory: directory, keyProvider: KeyProvider())
        }
        #expect(throws: (any Error).self) {
            try CaptureBodyStore.load(reference: "../outside.gcm", flowID: "test-flow", phase: "response",
                                      directory: directory, keyProvider: KeyProvider())
        }
    }
}
