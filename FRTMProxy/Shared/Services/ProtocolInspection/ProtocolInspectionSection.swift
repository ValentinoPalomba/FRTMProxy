import Foundation

struct ProtocolInspectionSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let content: String

    init(id: String, title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}
