import Foundation

struct SessionFlowUpsertSummary: Equatable, Sendable {
    var insertedFlowCount: Int
    var updatedFlowCount: Int
    var latestFlowDate: Date?

    static let empty = SessionFlowUpsertSummary(
        insertedFlowCount: 0,
        updatedFlowCount: 0,
        latestFlowDate: nil
    )

    mutating func merge(_ other: SessionFlowUpsertSummary) {
        insertedFlowCount += other.insertedFlowCount
        updatedFlowCount += other.updatedFlowCount
        latestFlowDate = [latestFlowDate, other.latestFlowDate].compactMap { $0 }.max()
    }
}

protocol SessionStoreProtocol: Actor {
    static var schemaVersion: Int { get }

    func importSession(_ prepared: SessionHARImporter.Prepared, name: String) throws -> CaptureSession
    func createSession(name: String, at date: Date) throws -> CaptureSession
    func activeSessionOrCreate(name: String, at date: Date) throws -> CaptureSession
    func sessions() throws -> [CaptureSession]
    func session(id: UUID) throws -> CaptureSession?
    func closeSession(id: UUID, at date: Date) throws
    func markSessionIncomplete(id: UUID, reason: String) throws
    func deleteSession(id: UUID) throws
    func cleanupDeletedBodies() throws

    @discardableResult
    func upsert(flow: sending MitmFlow, in sessionID: UUID) throws -> SessionFlowUpsertSummary
    @discardableResult
    func upsert(flows: sending [MitmFlow], in sessionID: UUID) throws -> SessionFlowUpsertSummary
    func flow(id: String, in sessionID: UUID) throws -> CaptureSessionFlow?
    func page(
        in sessionID: UUID,
        after cursor: CaptureSessionPageCursor?,
        limit: Int
    ) throws -> CaptureSessionPage
    func setMetadata(
        flowID: String,
        sessionID: UUID,
        note: String?,
        isBookmarked: Bool
    ) throws

    @discardableResult
    func applyRetentionPolicy(_ policy: CaptureSessionRetentionPolicy) throws -> [UUID]
}

extension SessionStoreProtocol {
    func importSession(_ prepared: SessionHARImporter.Prepared, name: String) throws -> CaptureSession {
        throw SessionStoreError.database("Session store does not support HAR import")
    }
    func markSessionIncomplete(id: UUID, reason: String) throws {
        throw SessionStoreError.database("Session store cannot record incomplete capture status")
    }
    func cleanupDeletedBodies() throws {}

    func createSession(name: String) throws -> CaptureSession {
        try createSession(name: name, at: .now)
    }

    func closeSession(id: UUID) throws {
        try closeSession(id: id, at: .now)
    }

    func activeSessionOrCreate(name: String, at date: Date) throws -> CaptureSession {
        if let activeSession = try sessions().first(where: { $0.isActive && $0.incompleteReason == nil }) {
            return activeSession
        }
        return try createSession(name: name, at: date)
    }

    @discardableResult
    func upsert(flows incoming: sending [MitmFlow], in sessionID: UUID) throws -> SessionFlowUpsertSummary {
        var summary = SessionFlowUpsertSummary.empty
        for flow in incoming {
            try summary.merge(upsert(flow: flow, in: sessionID))
        }
        return summary
    }

    func page(
        in sessionID: UUID,
        after cursor: CaptureSessionPageCursor? = nil,
        limit: Int = 200
    ) throws -> CaptureSessionPage {
        try page(in: sessionID, after: cursor, limit: limit)
    }
}
