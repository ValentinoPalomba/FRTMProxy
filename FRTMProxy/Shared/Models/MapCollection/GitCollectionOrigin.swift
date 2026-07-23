import Foundation

struct GitCollectionOrigin: Hashable, Codable, Sendable {
    let sourceID: UUID
    let remoteURL: String
    let reference: String
    let relativePath: String
    var commit: String?
}
