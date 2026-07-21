import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import FRTMProxy

final class SessionStoreTests: XCTestCase {
    private struct FixedKeyProvider: SessionEncryptionKeyProviding {
        let data: Data

        func loadOrCreateKey() throws -> SymmetricKey {
            SymmetricKey(data: data)
        }
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FRTMProxySessionStoreTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "sessions.sqlite")
    }

    private func makeStore(at url: URL) throws -> SQLiteSessionStore {
        try SQLiteSessionStore(
            databaseURL: url,
            keyProvider: FixedKeyProvider(data: Data(repeating: 0x2A, count: 32))
        )
    }

    private func flow(
        id: String,
        event: String = "request",
        timestamp: TimeInterval,
        requestBody: String = "request-secret",
        responseBody: String? = nil
    ) -> MitmFlow {
        let response: String
        if let responseBody {
            response = """
            ,"response":{"status":200,"headers":{"Content-Type":"application/json"},"body":"\(responseBody)"}
            """
        } else {
            response = ",\"response\":null"
        }
        return FlowFixture.make(
            """
            {
              "id":"\(id)","event":"\(event)","timestamp":\(timestamp),
              "request":{"method":"POST","url":"https://example.com/\(id)","headers":{"Authorization":"Bearer sensitive-token"},"body":"\(requestBody)"}
              \(response)
            }
            """
        )
    }

    func testCRUDAndRequestResponseUpsertPreservePayload() async throws {
        let url = try temporaryDatabaseURL()
        let store = try makeStore(at: url)
        let session = try await store.createSession(name: "API capture", at: Date(timeIntervalSince1970: 10))

        try await store.upsert(flow: flow(id: "f1", timestamp: 11), in: session.id)
        try await store.upsert(
            flow: flow(id: "f1", event: "response", timestamp: 12, responseBody: "response-secret"),
            in: session.id
        )

        let stored = try await store.flow(id: "f1", in: session.id)
        XCTAssertEqual(stored?.flow.request?.body, "request-secret")
        XCTAssertEqual(stored?.flow.response?.body, "response-secret")
        try await store.setMetadata(
            flowID: "f1",
            sessionID: session.id,
            note: "private investigation note",
            isBookmarked: true
        )
        let annotated = try await store.flow(id: "f1", in: session.id)
        XCTAssertEqual(annotated?.note, "private investigation note")
        XCTAssertEqual(annotated?.isBookmarked, true)
        let updatedSession = try await store.session(id: session.id)
        XCTAssertEqual(updatedSession?.flowCount, 1)

        try await store.closeSession(id: session.id, at: Date(timeIntervalSince1970: 20))
        let closedSession = try await store.session(id: session.id)
        XCTAssertEqual(closedSession?.isActive, false)
        try await store.deleteSession(id: session.id)
        let deletedSession = try await store.session(id: session.id)
        XCTAssertNil(deletedSession)
    }

    func testKeysetPagingIsStableAndDeterministic() async throws {
        let url = try temporaryDatabaseURL()
        let store = try makeStore(at: url)
        let session = try await store.createSession(name: "Paging", at: .distantPast)
        for index in 0..<7 {
            try await store.upsert(
                flow: flow(id: "flow-\(index)", timestamp: TimeInterval(index)),
                in: session.id
            )
        }

        let first = try await store.page(in: session.id, after: nil, limit: 3)
        let second = try await store.page(in: session.id, after: first.nextCursor, limit: 3)
        let third = try await store.page(in: session.id, after: second.nextCursor, limit: 3)
        XCTAssertEqual(first.flows.map(\.id), ["flow-6", "flow-5", "flow-4"])
        XCTAssertEqual(second.flows.map(\.id), ["flow-3", "flow-2", "flow-1"])
        XCTAssertEqual(third.flows.map(\.id), ["flow-0"])
        XCTAssertNil(third.nextCursor)
        XCTAssertEqual(Set((first.flows + second.flows + third.flows).map(\.id)).count, 7)
    }

    func testDatabaseReopensAndMigrationIsIdempotent() async throws {
        let url = try temporaryDatabaseURL()
        let firstStore = try makeStore(at: url)
        let session = try await firstStore.createSession(name: "Recovered", at: .now)
        try await firstStore.upsert(flow: flow(id: "persisted", timestamp: 1), in: session.id)

        let reopenedStore = try makeStore(at: url)
        let persisted = try await reopenedStore.flow(id: "persisted", in: session.id)
        let reopenedSessions = try await reopenedStore.sessions()
        XCTAssertEqual(persisted?.flow.request?.body, "request-secret")
        XCTAssertEqual(reopenedSessions.map(\.id), [session.id])
    }

    func testSensitivePayloadIsEncryptedAtRest() async throws {
        let url = try temporaryDatabaseURL()
        let store = try makeStore(at: url)
        let session = try await store.createSession(name: "Encrypted", at: .now)
        try await store.upsert(flow: flow(id: "secure", timestamp: 1), in: session.id)

        let databaseBytes = try Data(contentsOf: url)
        let databaseText = String(decoding: databaseBytes, as: UTF8.self)
        XCTAssertFalse(databaseText.localizedStandardContains("Bearer sensitive-token"))
        XCTAssertFalse(databaseText.localizedStandardContains("request-secret"))
    }

    func testCorruptPayloadIsReportedWithoutHidingHealthyRows() async throws {
        let url = try temporaryDatabaseURL()
        let store = try makeStore(at: url)
        let session = try await store.createSession(name: "Corruption", at: .now)
        try await store.upsert(flow: flow(id: "healthy", timestamp: 2), in: session.id)
        try await store.upsert(flow: flow(id: "broken", timestamp: 1), in: session.id)
        try corruptPayload(flowID: "broken", sessionID: session.id, databaseURL: url)

        let page = try await store.page(in: session.id, after: nil, limit: 10)
        XCTAssertEqual(page.flows.map(\.id), ["healthy"])
        XCTAssertEqual(page.corruptFlowIDs, ["broken"])
    }

    func testCorruptDatabaseIsRejected() throws {
        let url = try temporaryDatabaseURL()
        try Data("not-a-sqlite-database".utf8).write(to: url)
        XCTAssertThrowsError(try makeStore(at: url))
    }

    func testRetentionRemovesOldAndExcessClosedSessions() async throws {
        let url = try temporaryDatabaseURL()
        let store = try makeStore(at: url)
        let old = try await store.createSession(name: "Old", at: Date(timeIntervalSince1970: 1))
        let middle = try await store.createSession(name: "Middle", at: Date(timeIntervalSince1970: 2))
        let newest = try await store.createSession(name: "Newest", at: Date(timeIntervalSince1970: 3))
        try await store.upsert(flow: flow(id: "old-flow", timestamp: 1), in: old.id)
        try await store.closeSession(id: old.id, at: Date(timeIntervalSince1970: 1))
        try await store.closeSession(id: middle.id, at: Date(timeIntervalSince1970: 2))
        try await store.closeSession(id: newest.id, at: Date(timeIntervalSince1970: 3))

        let deleted = try await store.applyRetentionPolicy(
            CaptureSessionRetentionPolicy(maximumSessions: 1, sessionsOlderThan: Date(timeIntervalSince1970: 2))
        )
        let retainedSessions = try await store.sessions()
        let removedFlow = try await store.flow(id: "old-flow", in: old.id)
        XCTAssertEqual(Set(deleted), Set([old.id, middle.id]))
        XCTAssertEqual(retainedSessions.map(\.id), [newest.id])
        XCTAssertNil(removedFlow)
    }

    private func corruptPayload(flowID: String, sessionID: UUID, databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw SessionStoreError.database("Unable to open test database")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "UPDATE flows SET encrypted_payload = X'00010203' WHERE session_id = ? AND flow_id = ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SessionStoreError.database("Unable to prepare corruption fixture")
        }
        defer { sqlite3_finalize(statement) }
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, flowID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SessionStoreError.database("Unable to corrupt fixture")
        }
    }
}
