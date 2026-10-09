import CryptoKit
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Captured HAR import")
struct SessionHARImporterTests {
    @Test func binaryDuplicatesTimingAndEncryptedOriginals() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "har-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bodies = directory.appending(path: "Bodies")
        let bytes = Data(repeating: 0xff, count: 3 * 1024 * 1024)
        var flow = MitmFlow(id: "exported", event: "response")
        flow.requestTimestamp = 100.125
        flow.responseTimestamp = 100.375
        flow.request = .init(method: "GET", url: "https://example.com/data", headers: [:], body: nil,
                             httpVersion: "HTTP/2", headerFields: [.init(name: "X-Repeated", value: "one"),
                                .init(name: "X-Repeated", value: "two"), .init(name: "X-Empty", value: "")])
        flow.response = .init(status: 200, headers: [:], body: "data:application/octet-stream;base64," + bytes.base64EncodedString(),
                              httpVersion: "HTTP/2", byteCount: bytes.count)
        let prepared = try SessionHARImporter.prepare(SessionHARExporter.data(flows: [flow], redacted: false))
        #expect(prepared.items.first?.responseBody == bytes)
        #expect(prepared.items.first?.flow.request?.headerFields?.map(\.value) == ["one", "two", ""])
        #expect(prepared.items.first?.flow.duration == 0.25)
        #expect(prepared.items.first?.flow.requestTimestamp == 100.125)
        #expect(prepared.items.first?.flow.response?.bodyTruncated == true)
        let provider = CaptureStorageConfiguration.keyProvider
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "capture.sqlite"), keyProvider: provider, bodyDirectory: bodies)
        let session = try await store.importSession(prepared, name: "Imported")
        #expect(!session.isActive)
        #expect(session.flowCount == 1)
        let saved = try await store.page(in: session.id, limit: 10)
        let stored = try #require(saved.flows.first?.flow)
        #expect(stored.request?.headerFields?.count == 3)
        let reference = try #require(stored.response?.originalBodyReference)
        #expect(try CaptureBodyStore.load(reference: reference, flowID: stored.id, phase: "response", directory: bodies, keyProvider: provider) == bytes)
        let ciphertext = try Data(contentsOf: bodies.appending(path: reference))
        #expect(ciphertext != bytes)
    }

    @Test func failedBodyWriteRollsBackSessionAndDoesNotTouchExistingCapture() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "har-import-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedDirectory = directory.appending(path: "file-not-directory")
        try Data("blocked".utf8).write(to: blockedDirectory)
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "capture.sqlite"),
                                           keyProvider: CaptureStorageConfiguration.keyProvider, bodyDirectory: blockedDirectory)
        let original = try await store.createSession(name: "Existing")
        var flow = MitmFlow(id: "imported", event: "response")
        flow.requestTimestamp = 100
        flow.request = .init(method: "GET", url: "https://example.com", headers: [:], body: nil)
        flow.response = .init(status: 200, headers: [:], body: "original bytes")
        let prepared = try SessionHARImporter.prepare(SessionHARExporter.data(flows: [flow], redacted: false))
        await #expect(throws: (any Error).self) { try await store.importSession(prepared, name: "Failed") }
        let sessions = try await store.sessions()
        #expect(sessions.map(\.id) == [original.id])
        #expect(try Data(contentsOf: blockedDirectory) == Data("blocked".utf8))
    }

    @Test func redactedExportDoesNotInventMissingBodiesOrTiming() throws {
        var flow = MitmFlow(id: "redacted", event: "response")
        flow.requestTimestamp = 100
        flow.request = .init(method: "GET", url: "https://example.com?token=secret", headers: [:], body: nil)
        flow.response = .init(status: 200, headers: [:], body: "secret")
        let prepared = try SessionHARImporter.prepare(SessionHARExporter.data(flows: [flow]))
        #expect(prepared.items.first?.responseBody == nil)
        #expect(prepared.items.first?.flow.responseTimestamp == nil)
        #expect(prepared.items.first?.flow.request?.url.contains("secret") == false)
    }
}
