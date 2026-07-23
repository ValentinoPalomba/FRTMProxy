import Foundation

struct WorkspaceManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    let identifier: String
    var displayName: String
    var summary: String?
    var resources: WorkspaceResources

    init(
        schemaVersion: Int = WorkspaceFormat.currentSchemaVersion,
        identifier: String,
        displayName: String,
        summary: String? = nil,
        resources: WorkspaceResources = WorkspaceResources()
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.displayName = displayName
        self.summary = summary
        self.resources = resources
    }
}
