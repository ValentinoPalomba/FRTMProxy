import CryptoKit
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Composer templates and encrypted history")
struct ComposerWorkflowTests {
    private struct KeyProvider: SessionEncryptionKeyProviding {
        let byte: UInt8
        func loadOrCreateKey() throws -> SymmetricKey { SymmetricKey(data: Data(repeating: byte, count: 32)) }
    }
    @Test @MainActor func replayPreservesBytesAndRefusesIncompletePreview() async throws {
        let original = Data([0, 255, 13, 10, 128])
        var draft = ComposerDraft(method: "GET", url: "http://example.com/a/../b?ids[0]=1",
            headers: [.init(key: "X-Duplicate", value: "one"), .init(key: "X-Duplicate", value: "two"),
                      .init(key: "Content-Length", value: "99")], body: original.base64EncodedString(), bodyIsBase64: true)
        let request = try ComposerTemplate.request(draft, variables: [])
        #expect(request.body == original)
        #expect(request.headers == [.init(name: "X-Duplicate", value: "one"), .init(name: "X-Duplicate", value: "two")])
        draft.body = "not base64!"
        #expect(throws: (any Error).self) { try ComposerTemplate.request(draft, variables: []) }
        draft.body = Data(repeating: 1, count: 2 * 1024 * 1024).base64EncodedString()
        #expect(try ComposerTemplate.request(draft, variables: []).body?.count == 2 * 1024 * 1024)
        draft.body += "AAAA"
        #expect(throws: (any Error).self) { try ComposerTemplate.request(draft, variables: []) }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = RequestComposerViewModel(store: ComposerStateStore(url: directory.appending(path: "state"), keyProvider: KeyProvider(byte: 1)))
        func flow(truncated: Bool) throws -> MitmFlow {
            let object: [String: Any] = ["id": "binary-flow", "event": "request", "request": ["method": "POST", "url": "http://example.com", "headers": [:], "body": "data:application/octet-stream;base64," + original.base64EncodedString(), "bodyTruncated": truncated]]
            return try JSONDecoder().decode(MitmFlow.self, from: JSONSerialization.data(withJSONObject: object))
        }
        await model.loadFromFlow(try flow(truncated: false))
        #expect(model.bodyIsBase64)
        #expect(Data(base64Encoded: model.requestBody) == original)
        await model.loadFromFlow(try flow(truncated: true))
        #expect(model.urlString.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
        // Legacy encrypted drafts remain readable when the new optional field is absent.
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","date":0,"method":"GET","url":"http://example.com","headers":[],"body":"text"}"#.utf8)
        #expect(try JSONDecoder().decode(ComposerDraft.self, from: legacy).bodyIsBase64 == nil)
    }
    @Test func templatesResolveOnceAndRejectUnresolvedVariablesAndHeaderInjection() throws {
        let draft = ComposerDraft(method: "POST", url: "{{BASE}}/users", headers: [.init(key: "Authorization", value: "Bearer {{TOKEN}}")], body: "{\"id\":{{ID}}}")
        let variables = [ComposerHeaderRow(key: "BASE", value: "https://example.com"), .init(key: "TOKEN", value: "secret{{LITERAL}}"), .init(key: "ID", value: "42")]
        let request = try ComposerTemplate.request(draft, variables: variables)
        #expect(request.url.absoluteString == "https://example.com/users")
        #expect(request.headers.first(where: { $0.name == "Authorization" })?.value == "Bearer secret{{LITERAL}}")
        #expect(request.body == Data("{\"id\":42}".utf8))
        #expect(throws: (any Error).self) { try ComposerTemplate.request(draft, variables: []) }
        #expect(throws: (any Error).self) { try ComposerTemplate.request(draft, variables: variables + [variables[0]]) }
        var injected = draft
        injected.url = "https://example.com"
        injected.headers = [.init(key: "X-Test", value: "valid\r\nInjected: yes")]
        injected.body = ""
        #expect(throws: (any Error).self) { try ComposerTemplate.request(injected, variables: []) }
        injected.headers = []
        injected.url = "file:///etc/passwd"
        #expect(throws: (any Error).self) { try ComposerTemplate.request(injected, variables: []) }
    }
    @Test @MainActor func historyIsBoundedEncryptedAndUnreadableStateIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "composer.gcm")
        let store = ComposerStateStore(url: url, keyProvider: KeyProvider(byte: 1))
        let state = ComposerStateStore.State(history: (0..<60).map { .init(method: "GET", url: "https://example.com/\($0)", headers: [], body: "request-secret") }, variables: [.init(key: "TOKEN", value: "variable-secret")])
        let saved = try await store.save(state)
        #expect(saved.history.count == 50)
        #expect(saved.history.last?.url == "https://example.com/49")
        #expect(try await store.load() == saved)
        let ciphertext = try Data(contentsOf: url)
        #expect(!String(decoding: ciphertext, as: UTF8.self).contains("variable-secret"))
        #expect(!String(decoding: ciphertext, as: UTF8.self).contains("request-secret"))
        let wrongKey = ComposerStateStore(url: url, keyProvider: KeyProvider(byte: 2))
        let model = RequestComposerViewModel(store: wrongKey)
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isRestoring, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.restoreFailed)
        model.variables = [.init(key: "TOKEN", value: "new-value")]
        await model.saveLocalState()
        #expect(try Data(contentsOf: url) == ciphertext)
        await model.resetLocalState()
        #expect(!model.restoreFailed)
        #expect(try await wrongKey.load() == .init())
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent.contains("backup-") })
    }
}
