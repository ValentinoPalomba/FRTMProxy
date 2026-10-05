import Foundation

struct ComposerHeaderRow: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var key: String
    var value: String
    init(id: UUID = UUID(), key: String, value: String) { self.id = id; self.key = key; self.value = value }
    static func makeRows(from headers: [String: String]) -> [ComposerHeaderRow] {
        headers.sorted { $0.key.lowercased() < $1.key.lowercased() }.map { .init(key: $0.key, value: $0.value) }
    }
}
