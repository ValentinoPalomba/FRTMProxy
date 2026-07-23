import Foundation

struct WorkspaceResourceReference: Codable, Equatable, Hashable, Sendable {
    let identifier: String
    let path: String

    init(identifier: String, path: String) {
        self.identifier = identifier
        self.path = path
    }
}
