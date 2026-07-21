import Foundation

protocol SessionStoreProtocol: Actor {
    static var schemaVersion: Int { get }

    func createSession(name: String, at date: Date) throws -> CaptureSession
    func sessions() throws -> [CaptureSession]
    func session(id: UUID) throws -> CaptureSession?
    func closeSession(id: UUID, at date: Date) throws
    func deleteSession(id: UUID) throws

    func upsert(flow: sending MitmFlow, in sessionID: UUID) throws
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
    func createSession(name: String) throws -> CaptureSession {
        try createSession(name: name, at: .now)
    }

    func closeSession(id: UUID) throws {
        try closeSession(id: id, at: .now)
    }

    func page(
        in sessionID: UUID,
        after cursor: CaptureSessionPageCursor? = nil,
        limit: Int = 200
    ) throws -> CaptureSessionPage {
        try page(in: sessionID, after: cursor, limit: limit)
    }
}
