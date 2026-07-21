import Foundation

struct WorkspaceResourcePayload: Equatable, Sendable {
    let kind: WorkspaceResourceKind
    let reference: WorkspaceResourceReference
    let data: Data

    init(kind: WorkspaceResourceKind, reference: WorkspaceResourceReference, data: Data) {
        self.kind = kind
        self.reference = reference
        self.data = data
    }
}

struct WorkspaceBundle: Equatable, Sendable {
    let manifest: WorkspaceManifest
    let resources: [WorkspaceResourcePayload]

    init(manifest: WorkspaceManifest, resources: [WorkspaceResourcePayload]) {
        self.manifest = manifest
        self.resources = resources
    }
}

struct WorkspaceServiceLimits: Equatable, Sendable {
    static let defaults = WorkspaceServiceLimits()

    let validation: WorkspaceValidationLimits
    let maximumResourceBytes: Int
    let maximumTotalResourceBytes: Int

    init(
        validation: WorkspaceValidationLimits = .defaults,
        maximumResourceBytes: Int = 25 * 1_024 * 1_024,
        maximumTotalResourceBytes: Int = 250 * 1_024 * 1_024
    ) {
        self.validation = validation
        self.maximumResourceBytes = maximumResourceBytes
        self.maximumTotalResourceBytes = maximumTotalResourceBytes
    }

    func validate() throws {
        guard maximumResourceBytes > 0, maximumTotalResourceBytes > 0 else {
            throw WorkspaceServiceError.invalidLimits
        }
        guard maximumResourceBytes <= maximumTotalResourceBytes else {
            throw WorkspaceServiceError.invalidLimits
        }
    }
}
