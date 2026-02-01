import Foundation

struct GitCollectionSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var remoteURL: String
    var reference: String
    var subdirectory: String?
    var createdAt: Date
    var lastSyncedAt: Date?
    var lastSyncedCommit: String?

    init(
        id: UUID = UUID(),
        remoteURL: String,
        reference: String,
        subdirectory: String? = nil,
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        lastSyncedCommit: String? = nil
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.reference = reference
        self.subdirectory = subdirectory
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedCommit = lastSyncedCommit
    }
}
