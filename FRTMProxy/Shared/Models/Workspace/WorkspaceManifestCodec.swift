import Foundation

enum WorkspaceManifestCodec {
    static func encode(_ manifest: WorkspaceManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func decode(
        _ data: Data,
        limits: WorkspaceValidationLimits = .defaults
    ) throws -> WorkspaceManifest {
        guard data.count <= limits.maximumManifestBytes else {
            throw WorkspaceValidationError.manifestTooLarge(limit: limits.maximumManifestBytes)
        }
        let manifest = try JSONDecoder().decode(WorkspaceManifest.self, from: data)
        try WorkspaceImportValidator.validate(manifest, limits: limits)
        return manifest
    }
}
