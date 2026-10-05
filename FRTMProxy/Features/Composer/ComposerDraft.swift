import Foundation

struct ComposerDraft: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date = Date.now
    var method: String
    var url: String
    var headers: [ComposerHeaderRow]
    var body: String
    var bodyIsBase64: Bool? = nil
}
