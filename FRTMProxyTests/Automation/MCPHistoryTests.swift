import CryptoKit
import Foundation
import Testing
@testable import FRTMProxy

@Suite("MCP encrypted history")
struct MCPHistoryTests {
    private struct KeyProvider: SessionEncryptionKeyProviding {
        func loadOrCreateKey() throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 0x31, count: 32)) }
    }

    private func call(_ name: String, arguments: [String: Any], router: MCPAutomationRouter) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                                  "params": ["name": name, "arguments": arguments]])
        let bytes = try #require(await router.handle(request))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("fixture-secret"))
        let response = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        return try #require(response["result"] as? [String: Any])
    }

    private func content(_ result: [String: Any]) throws -> [String: Any] {
        #expect(result["isError"] as? Bool == false)
        let items = try #require(result["content"] as? [[String: Any]])
        let text = try #require(items.first?["text"] as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @MainActor
    private final class StoreHolder {
        var store: (any SessionStoreProtocol)?
    }

    @Test @MainActor
    func sessionProviderResolvesStorageInstalledAfterRouterCreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let holder = StoreHolder()
        let router = MCPAutomationRouter(sessionStoreProvider: { holder.store }, flowProvider: { [] }, ruleUpdater: { _ in })
        let unavailable = try await call("list_sessions", arguments: [:], router: router)
        #expect(unavailable["isError"] as? Bool == true)
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: KeyProvider())
        let session = try await store.createSession(name: "Late storage")
        try await store.upsert(flow: MitmFlow(id: "late-flow", event: "response"), in: session.id)
        holder.store = store
        let listing = try content(await call("list_sessions", arguments: [:], router: router))
        #expect((listing["sessions"] as? [[String: Any]])?.first?["flowCount"] as? Int == 1)
        let page = try content(await call("query_session_flows", arguments: ["sessionID": session.id.uuidString], router: router))
        #expect((page["flows"] as? [[String: Any]])?.first?["id"] as? String == "late-flow")
        holder.store = nil
        let removed = try await call("list_sessions", arguments: [:], router: router)
        #expect(removed["isError"] as? Bool == true)
    }

    @Test @MainActor
    func historyBeyondLiveCacheAndEmptyMatchPagesRemainReachable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteSessionStore(databaseURL: directory.appending(path: "session.sqlite"), keyProvider: KeyProvider())
        let session = try await store.createSession(name: "Historic capture")
        var flows: [MitmFlow] = []
        for index in 0..<501 {
            flows.append(try JSONDecoder().decode(MitmFlow.self, from: Data("""
            {"id":"flow-\(index)","event":"response","requestTimestamp":\(index),"responseTimestamp":\(index + 1),
             "request":{"method":"GET","url":"https://user:fixture-secret@example.com/data?token=fixture-secret", "headers":{"Authorization":"fixture-secret"},"body":"fixture-secret"},
             "response":{"status":\(index == 0 ? 500 : 200),"headers":{"Set-Cookie":"fixture-secret"},"body":"fixture-secret"}}
            """.utf8)))
        }
        try await store.upsert(flows: flows, in: session.id)
        let router = MCPAutomationRouter(sessionStore: store, flowProvider: { [] }, ruleUpdater: { _ in throw CocoaError(.fileWriteNoPermission) })
        let listing = try content(await call("list_sessions", arguments: [:], router: router))
        #expect((listing["sessions"] as? [[String: Any]])?.first?["flowCount"] as? Int == 501)
        var cursor: String?
        var ids: [String] = []
        repeat {
            var arguments: [String: Any] = ["sessionID": session.id.uuidString, "limit": 120]
            if let cursor { arguments["cursor"] = cursor }
            let page = try content(await call("query_session_flows", arguments: arguments, router: router))
            let results = try #require(page["flows"] as? [[String: Any]])
            ids += results.compactMap { $0["id"] as? String }
            cursor = page["nextCursor"] as? String
        } while cursor != nil
        #expect(ids.count == 501)
        #expect(Set(ids).count == 501)
        #expect(ids.first == "flow-500")
        #expect(ids.last == "flow-0")

        let emptyMatch = try content(await call("query_session_flows", arguments: ["sessionID": session.id.uuidString, "limit": 500, "query": "status:500"], router: router))
        #expect((emptyMatch["flows"] as? [[String: Any]])?.isEmpty == true)
        let next = try #require(emptyMatch["nextCursor"] as? String)
        let final = try content(await call("query_session_flows", arguments: ["sessionID": session.id.uuidString, "cursor": next, "query": "status:500"], router: router))
        #expect((final["flows"] as? [[String: Any]])?.first?["id"] as? String == "flow-0")
        #expect(final["nextCursor"] is NSNull)

        let detail = try content(await call("get_session_flow", arguments: ["sessionID": session.id.uuidString, "id": "flow-0"], router: router))
        #expect(detail["id"] as? String == "flow-0")
        #expect((detail["request"] as? [String: Any])?["bodyOmitted"] as? Bool == true)
        let malformed = try await call("query_session_flows", arguments: ["sessionID": session.id.uuidString, "cursor": "not-a-cursor"], router: router)
        #expect(malformed["isError"] as? Bool == true)
        for invalid: [String: Any] in [["limit": true], ["limit": 1.5], ["cursor": 3], ["query": false]] {
            var arguments = invalid
            arguments["sessionID"] = session.id.uuidString
            let failure = try await call("query_session_flows", arguments: arguments, router: router)
            #expect(failure["isError"] as? Bool == true)
        }
    }
}
