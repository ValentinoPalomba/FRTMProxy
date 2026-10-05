import CryptoKit
import Foundation
import SQLite3

enum SessionStoreError: Error, Equatable {
    case database(String)
    case unsupportedSchemaVersion(Int)
    case sessionNotFound(UUID)
    case invalidPageLimit
    case payloadAuthenticationFailed(String)
    case payloadEncodingFailed
}

actor SQLiteSessionStore: SessionStoreProtocol {
    static let schemaVersion = 2

    private struct EncryptedFlowEnvelope: Codable {
        var flow: MitmFlow
        var note: String?
        var websocketMessages: [WebSocketMessage]

        init(flow: MitmFlow, note: String?) {
            self.flow = flow
            self.note = note
            websocketMessages = flow.websocketMessages
        }
    }

    // SQLite is opened in FULLMUTEX mode and accessed only by this actor. The
    // unsafe annotation is required solely because actor deinit is nonisolated.
    nonisolated(unsafe) private let database: OpaquePointer
    private let encryptionKey: SymmetricKey
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let bodyDirectory: URL
    private var bodyReferencesIndexed = false

    init(
        databaseURL: URL,
        keyProvider: any SessionEncryptionKeyProviding = KeychainSessionEncryptionKeyProvider(),
        bodyDirectory: URL = CaptureBodyStore.directory
    ) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle { sqlite3_close(handle) }
            throw SessionStoreError.database(message)
        }
        database = handle
        self.bodyDirectory = bodyDirectory

        do {
            encryptionKey = try keyProvider.loadOrCreateKey()
            sqlite3_busy_timeout(database, 5_000)
            try Self.execute("PRAGMA foreign_keys = ON", on: database)
            try Self.execute("PRAGMA journal_mode = WAL", on: database)
            try Self.migrate(database)
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func createSession(name: String, at date: Date) throws -> CaptureSession {
        let id = UUID()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = normalizedName.isEmpty ? "Session" : normalizedName
        try withStatement(
            "INSERT INTO sessions(id, name, created_at, updated_at, ended_at) VALUES(?, ?, ?, ?, NULL)"
        ) { statement in
            bind(id.uuidString, at: 1, to: statement)
            bind(finalName, at: 2, to: statement)
            bind(date.timeIntervalSince1970, at: 3, to: statement)
            bind(date.timeIntervalSince1970, at: 4, to: statement)
            try stepDone(statement)
        }
        return CaptureSession(
            id: id,
            name: finalName,
            createdAt: date,
            updatedAt: date,
            endedAt: nil,
            flowCount: 0
        )
    }

    func sessions() throws -> [CaptureSession] {
        try querySessions(whereClause: "", bindings: { _ in })
    }

    func session(id: UUID) throws -> CaptureSession? {
        try querySessions(whereClause: "WHERE s.id = ?", bindings: { statement in
            bind(id.uuidString, at: 1, to: statement)
        }).first
    }

    func closeSession(id: UUID, at date: Date) throws {
        try requireSession(id)
        try withStatement("UPDATE sessions SET ended_at = ?, updated_at = ? WHERE id = ?") { statement in
            bind(date.timeIntervalSince1970, at: 1, to: statement)
            bind(date.timeIntervalSince1970, at: 2, to: statement)
            bind(id.uuidString, at: 3, to: statement)
            try stepDone(statement)
        }
    }

    func deleteSession(id: UUID) throws {
        try indexExistingBodyReferences()
        try transaction {
            try withStatement("INSERT OR IGNORE INTO body_cleanup(reference) SELECT reference FROM body_references WHERE session_id = ?") { statement in
                bind(id.uuidString, at: 1, to: statement)
                try stepDone(statement)
            }
            try withStatement("DELETE FROM sessions WHERE id = ?") { statement in
                bind(id.uuidString, at: 1, to: statement)
                try stepDone(statement)
            }
        }
        // Durable queue survives a crash or disk error after the database commit.
        try cleanupDeletedBodies()
    }

    private func recordBodyReferences(_ flow: MitmFlow, sessionID: UUID) throws {
        for reference in [flow.request?.originalBodyReference, flow.response?.originalBodyReference].compactMap({ $0 }) {
            guard CaptureBodyStore.isValidReference(reference) else { continue }
            try withStatement("INSERT OR IGNORE INTO body_references(session_id, reference) VALUES(?, ?)") { statement in
                bind(sessionID.uuidString, at: 1, to: statement)
                bind(reference, at: 2, to: statement)
                try stepDone(statement)
            }
        }
    }

    private func indexExistingBodyReferences() throws {
        guard !bodyReferencesIndexed else { return }
        let alreadyIndexed = try withStatement("SELECT completed FROM body_reference_state WHERE id = 1") { statement in
            sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 1
        }
        if alreadyIndexed { bodyReferencesIndexed = true; return }
        // Backfill old encrypted payloads before deleting anything. Authentication failure
        // stops cleanup instead of treating unreadable references as unreferenced files.
        try transaction {
            try withStatement("SELECT session_id, flow_id, encrypted_payload FROM flows") { statement in
                var result = sqlite3_step(statement)
                while result == SQLITE_ROW {
                    guard let sessionID = UUID(uuidString: columnString(statement, at: 0)) else {
                        throw SessionStoreError.payloadEncodingFailed
                    }
                    let flowID = columnString(statement, at: 1)
                    let envelope = try decrypt(columnData(statement, at: 2), flowID: flowID, sessionID: sessionID)
                    try recordBodyReferences(envelope.flow, sessionID: sessionID)
                    result = sqlite3_step(statement)
                }
                guard result == SQLITE_DONE else { throw SessionStoreError.database(String(cString: sqlite3_errmsg(database))) }
            }
            try Self.execute("INSERT OR REPLACE INTO body_reference_state(id, completed) VALUES(1, 1)", on: database)
        }
        bodyReferencesIndexed = true
    }

    func cleanupDeletedBodies() throws {
        try indexExistingBodyReferences()
        var pending: [String] = []
        try withStatement("SELECT reference FROM body_cleanup WHERE reference NOT IN (SELECT reference FROM body_references)") { statement in
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                pending.append(columnString(statement, at: 0))
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw SessionStoreError.database(String(cString: sqlite3_errmsg(database))) }
        }
        for reference in pending {
            guard CaptureBodyStore.isValidReference(reference) else { throw CocoaError(.fileReadInvalidFileName) }
            let url = bodyDirectory.appending(path: reference)
            do { try FileManager.default.removeItem(at: url) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { /* Already removed before a crash. */ }
            try withStatement("DELETE FROM body_cleanup WHERE reference = ?") { statement in
                bind(reference, at: 1, to: statement)
                try stepDone(statement)
            }
        }
        try transaction {
            _ = try CaptureBodyStore.pruneOrphans(directory: bodyDirectory, before: .now.addingTimeInterval(-24 * 60 * 60)) { reference in
                try withStatement("SELECT 1 FROM body_references WHERE reference = ? LIMIT 1") { statement in
                    bind(reference, at: 1, to: statement)
                    let result = sqlite3_step(statement)
                    guard result == SQLITE_ROW || result == SQLITE_DONE else {
                        throw SessionStoreError.database(String(cString: sqlite3_errmsg(database)))
                    }
                    return result == SQLITE_ROW
                }
            }
        }
    }

    @discardableResult
    func upsert(
        flow incoming: sending MitmFlow,
        in sessionID: UUID
    ) throws -> SessionFlowUpsertSummary {
        try upsert(flows: [incoming], in: sessionID)
    }

    @discardableResult
    func upsert(
        flows incoming: sending [MitmFlow],
        in sessionID: UUID
    ) throws -> SessionFlowUpsertSummary {
        guard !incoming.isEmpty else { return .empty }
        try requireSession(sessionID)
        var orderedFlowIDs: [String] = []
        var coalescedFlows: [String: MitmFlow] = [:]
        for flow in incoming {
            if let existing = coalescedFlows[flow.id] {
                coalescedFlows[flow.id] = existing.mergingSessionSnapshot(with: flow)
            } else {
                orderedFlowIDs.append(flow.id)
                coalescedFlows[flow.id] = flow
            }
        }
        return try transaction {
            var insertedFlowCount = 0
            for flowID in orderedFlowIDs {
                guard let flow = coalescedFlows[flowID] else { continue }
                if try upsertFlow(flow, in: sessionID) {
                    insertedFlowCount += 1
                }
            }
            let latestTimestamp = incoming.map(Self.sortTimestamp).max() ?? Date.now.timeIntervalSince1970
            try touchSession(sessionID, at: Date(timeIntervalSince1970: latestTimestamp))
            return SessionFlowUpsertSummary(
                insertedFlowCount: insertedFlowCount,
                updatedFlowCount: orderedFlowIDs.count - insertedFlowCount,
                latestFlowDate: Date(timeIntervalSince1970: latestTimestamp)
            )
        }
    }

    private func upsertFlow(_ incoming: MitmFlow, in sessionID: UUID) throws -> Bool {
        let existing = try encryptedEnvelope(flowID: incoming.id, sessionID: sessionID)
        let envelope: EncryptedFlowEnvelope
        let bookmarked: Bool
        if let existing {
            envelope = EncryptedFlowEnvelope(
                flow: existing.envelope.flow.mergingSessionSnapshot(with: incoming),
                note: existing.envelope.note
            )
            bookmarked = existing.isBookmarked
        } else {
            envelope = EncryptedFlowEnvelope(flow: incoming, note: nil)
            bookmarked = false
        }

        let payload = try encrypt(envelope, flowID: incoming.id, sessionID: sessionID)
        let timestamp = Self.sortTimestamp(envelope.flow)
        try withStatement(
            """
            INSERT INTO flows(session_id, flow_id, sort_timestamp, is_bookmarked, encrypted_payload)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(session_id, flow_id) DO UPDATE SET
                sort_timestamp = excluded.sort_timestamp,
                is_bookmarked = excluded.is_bookmarked,
                encrypted_payload = excluded.encrypted_payload
            """
        ) { statement in
            bind(sessionID.uuidString, at: 1, to: statement)
            bind(incoming.id, at: 2, to: statement)
            bind(timestamp, at: 3, to: statement)
            bind(bookmarked ? 1 : 0, at: 4, to: statement)
            bind(payload, at: 5, to: statement)
            try stepDone(statement)
        }
        try recordBodyReferences(envelope.flow, sessionID: sessionID)
        return existing == nil
    }

    func flow(id: String, in sessionID: UUID) throws -> CaptureSessionFlow? {
        guard let stored = try encryptedEnvelope(flowID: id, sessionID: sessionID) else { return nil }
        return CaptureSessionFlow(
            flow: stored.envelope.flow,
            note: stored.envelope.note,
            isBookmarked: stored.isBookmarked
        )
    }

    func page(
        in sessionID: UUID,
        after cursor: CaptureSessionPageCursor?,
        limit: Int
    ) throws -> CaptureSessionPage {
        guard (1...1_000).contains(limit) else { throw SessionStoreError.invalidPageLimit }
        try requireSession(sessionID)

        let cursorClause = cursor == nil
            ? ""
            : "AND (sort_timestamp < ? OR (sort_timestamp = ? AND flow_id < ?))"
        let sql = """
            SELECT flow_id, sort_timestamp, is_bookmarked, encrypted_payload
            FROM flows
            WHERE session_id = ? \(cursorClause)
            ORDER BY sort_timestamp DESC, flow_id DESC
            LIMIT ?
            """
        var rows: [(flowID: String, timestamp: TimeInterval, bookmarked: Bool, payload: Data)] = []
        try withStatement(sql) { statement in
            bind(sessionID.uuidString, at: 1, to: statement)
            var limitIndex: Int32 = 2
            if let cursor {
                bind(cursor.timestamp, at: 2, to: statement)
                bind(cursor.timestamp, at: 3, to: statement)
                bind(cursor.flowID, at: 4, to: statement)
                limitIndex = 5
            }
            bind(limit + 1, at: limitIndex, to: statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append((
                    columnString(statement, at: 0),
                    sqlite3_column_double(statement, 1),
                    sqlite3_column_int(statement, 2) != 0,
                    columnData(statement, at: 3)
                ))
            }
            try verifyLastStep(statement)
        }

        let pageRows = rows.prefix(limit)
        var result: [CaptureSessionFlow] = []
        var corruptIDs: [String] = []
        for row in pageRows {
            do {
                let envelope = try decrypt(row.payload, flowID: row.flowID, sessionID: sessionID)
                result.append(CaptureSessionFlow(
                    flow: envelope.flow,
                    note: envelope.note,
                    isBookmarked: row.bookmarked
                ))
            } catch SessionStoreError.payloadAuthenticationFailed {
                corruptIDs.append(row.flowID)
            }
        }
        let nextCursor = rows.count > limit
            ? pageRows.last.map { CaptureSessionPageCursor(timestamp: $0.timestamp, flowID: $0.flowID) }
            : nil

        return CaptureSessionPage(
            flows: result,
            nextCursor: nextCursor,
            corruptFlowIDs: corruptIDs
        )
    }

    func setMetadata(
        flowID: String,
        sessionID: UUID,
        note: String?,
        isBookmarked: Bool
    ) throws {
        guard var stored = try encryptedEnvelope(flowID: flowID, sessionID: sessionID) else { return }
        stored.envelope.note = note
        let payload = try encrypt(stored.envelope, flowID: flowID, sessionID: sessionID)
        try withStatement(
            "UPDATE flows SET is_bookmarked = ?, encrypted_payload = ? WHERE session_id = ? AND flow_id = ?"
        ) { statement in
            bind(isBookmarked ? 1 : 0, at: 1, to: statement)
            bind(payload, at: 2, to: statement)
            bind(sessionID.uuidString, at: 3, to: statement)
            bind(flowID, at: 4, to: statement)
            try stepDone(statement)
        }
    }

    @discardableResult
    func applyRetentionPolicy(_ policy: CaptureSessionRetentionPolicy) throws -> [UUID] {
        // An in-progress capture is never eligible for automatic deletion.
        let allSessions = try sessions().filter { !$0.isActive }
        var deletionIDs = Set<UUID>()
        if let cutoff = policy.sessionsOlderThan {
            deletionIDs.formUnion(allSessions.filter { $0.updatedAt < cutoff }.map(\.id))
        }
        if let maximum = policy.maximumSessions, maximum >= 0 {
            let retained = allSessions.filter { !deletionIDs.contains($0.id) }
            deletionIDs.formUnion(retained.dropFirst(maximum).map(\.id))
        }
        for id in deletionIDs { try deleteSession(id: id) }
        return deletionIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private static func migrate(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SessionStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let currentVersion = sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
        guard currentVersion <= schemaVersion else {
            throw SessionStoreError.unsupportedSchemaVersion(currentVersion)
        }
        if currentVersion < 1 {
            try execute("BEGIN IMMEDIATE", on: database)
            do {
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS sessions(
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        ended_at REAL
                    )
                    """,
                    on: database
                )
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS flows(
                        session_id TEXT NOT NULL,
                        flow_id TEXT NOT NULL,
                        sort_timestamp REAL NOT NULL,
                        is_bookmarked INTEGER NOT NULL DEFAULT 0,
                        encrypted_payload BLOB NOT NULL,
                        PRIMARY KEY(session_id, flow_id),
                        FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
                    ) WITHOUT ROWID
                    """,
                    on: database
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS flow_page_index ON flows(session_id, sort_timestamp DESC, flow_id DESC)",
                    on: database
                )
                try execute("PRAGMA user_version = 1", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if currentVersion < 2 {
            try execute("BEGIN IMMEDIATE", on: database)
            do {
                try execute("CREATE TABLE body_references(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, reference TEXT NOT NULL, PRIMARY KEY(session_id, reference)) WITHOUT ROWID", on: database)
                try execute("CREATE INDEX body_reference_lookup ON body_references(reference)", on: database)
                try execute("CREATE TABLE body_cleanup(reference TEXT PRIMARY KEY NOT NULL) WITHOUT ROWID", on: database)
                try execute("PRAGMA user_version = 2", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        try execute("CREATE TABLE IF NOT EXISTS body_reference_state(id INTEGER PRIMARY KEY CHECK(id = 1), completed INTEGER NOT NULL)", on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SessionStoreError.database(message)
        }
    }

    private func querySessions(
        whereClause: String,
        bindings: (OpaquePointer) -> Void
    ) throws -> [CaptureSession] {
        let sql = """
            SELECT s.id, s.name, s.created_at, s.updated_at, s.ended_at, COUNT(f.flow_id)
            FROM sessions s LEFT JOIN flows f ON f.session_id = s.id
            \(whereClause)
            GROUP BY s.id
            ORDER BY s.updated_at DESC, s.id DESC
            """
        var result: [CaptureSession] = []
        try withStatement(sql) { statement in
            bindings(statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = UUID(uuidString: columnString(statement, at: 0)) else { continue }
                result.append(CaptureSession(
                    id: id,
                    name: columnString(statement, at: 1),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    endedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL
                        ? nil
                        : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    flowCount: Int(sqlite3_column_int64(statement, 5))
                ))
            }
            try verifyLastStep(statement)
        }
        return result
    }

    private func requireSession(_ id: UUID) throws {
        let exists = try withStatement("SELECT 1 FROM sessions WHERE id = ? LIMIT 1") { statement in
            bind(id.uuidString, at: 1, to: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW || result == SQLITE_DONE else { throw databaseError() }
            return result == SQLITE_ROW
        }
        guard exists else { throw SessionStoreError.sessionNotFound(id) }
    }

    private func touchSession(_ id: UUID, at date: Date) throws {
        try withStatement("UPDATE sessions SET updated_at = MAX(updated_at, ?) WHERE id = ?") { statement in
            bind(date.timeIntervalSince1970, at: 1, to: statement)
            bind(id.uuidString, at: 2, to: statement)
            try stepDone(statement)
        }
    }

    private func encryptedEnvelope(
        flowID: String,
        sessionID: UUID
    ) throws -> (envelope: EncryptedFlowEnvelope, isBookmarked: Bool)? {
        try withStatement(
            "SELECT is_bookmarked, encrypted_payload FROM flows WHERE session_id = ? AND flow_id = ?"
        ) { statement in
            bind(sessionID.uuidString, at: 1, to: statement)
            bind(flowID, at: 2, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw databaseError() }
            let payload = columnData(statement, at: 1)
            return (
                try decrypt(payload, flowID: flowID, sessionID: sessionID),
                sqlite3_column_int(statement, 0) != 0
            )
        }
    }

    private func encrypt(
        _ envelope: EncryptedFlowEnvelope,
        flowID: String,
        sessionID: UUID
    ) throws -> Data {
        guard let encoded = try? encoder.encode(envelope) else {
            throw SessionStoreError.payloadEncodingFailed
        }
        let sealed = try AES.GCM.seal(
            encoded,
            using: encryptionKey,
            authenticating: associatedData(flowID: flowID, sessionID: sessionID)
        )
        guard let combined = sealed.combined else { throw SessionStoreError.payloadEncodingFailed }
        return combined
    }

    private func decrypt(
        _ payload: Data,
        flowID: String,
        sessionID: UUID
    ) throws -> EncryptedFlowEnvelope {
        do {
            let box = try AES.GCM.SealedBox(combined: payload)
            let cleartext = try AES.GCM.open(
                box,
                using: encryptionKey,
                authenticating: associatedData(flowID: flowID, sessionID: sessionID)
            )
            var envelope = try decoder.decode(EncryptedFlowEnvelope.self, from: cleartext)
            // MitmFlow intentionally treats WebSocket messages as transient in its
            // bridge Codable shape; the encrypted envelope persists them separately.
            envelope.flow.websocketMessages = envelope.websocketMessages
            return envelope
        } catch {
            throw SessionStoreError.payloadAuthenticationFailed(flowID)
        }
    }

    private func associatedData(flowID: String, sessionID: UUID) -> Data {
        Data("frtm-session-v1|\(sessionID.uuidString)|\(flowID)".utf8)
    }

    private static func sortTimestamp(_ flow: MitmFlow) -> TimeInterval {
        flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp ?? Date.now.timeIntervalSince1970
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            let value = try body()
            try Self.execute("COMMIT", on: database)
            return value
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func verifyLastStep(_ statement: OpaquePointer) throws {
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func databaseError() -> SessionStoreError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func bind(_ value: Double, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ value: Int, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.sqliteTransient)
        }
    }

    private func columnString(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer, at index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
