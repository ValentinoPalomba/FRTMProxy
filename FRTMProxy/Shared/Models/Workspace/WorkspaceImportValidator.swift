import Foundation

struct WorkspaceValidationLimits: Codable, Equatable, Sendable {
    static let defaults = WorkspaceValidationLimits()

    let maximumManifestBytes: Int
    let maximumReferences: Int
    let maximumPathBytes: Int

    init(
        maximumManifestBytes: Int = 1_048_576,
        maximumReferences: Int = 10_000,
        maximumPathBytes: Int = 1_024
    ) {
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumReferences = maximumReferences
        self.maximumPathBytes = maximumPathBytes
    }
}

enum WorkspaceImportValidator {
    static func validate(
        _ manifest: WorkspaceManifest,
        limits: WorkspaceValidationLimits = .defaults
    ) throws {
        guard manifest.schemaVersion == WorkspaceFormat.currentSchemaVersion else {
            throw WorkspaceValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard !manifest.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceValidationError.emptyManifestIdentifier
        }
        guard !manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceValidationError.emptyDisplayName
        }
        guard manifest.resources.count <= limits.maximumReferences else {
            throw WorkspaceValidationError.tooManyReferences(limit: limits.maximumReferences)
        }

        var seenPaths: Set<String> = []
        try validate(manifest.resources.rules, kind: .rule, limits: limits, seenPaths: &seenPaths)
        try validate(manifest.resources.scripts, kind: .script, limits: limits, seenPaths: &seenPaths)
        try validate(manifest.resources.breakpoints, kind: .breakpoint, limits: limits, seenPaths: &seenPaths)
        try validate(manifest.resources.profiles, kind: .profile, limits: limits, seenPaths: &seenPaths)
        try validate(manifest.resources.sessions, kind: .session, limits: limits, seenPaths: &seenPaths)
        try validate(manifest.resources.policies, kind: .policy, limits: limits, seenPaths: &seenPaths)
    }

    static func resolve(
        _ reference: WorkspaceResourceReference,
        kind: WorkspaceResourceKind,
        inside workspaceRoot: URL,
        limits: WorkspaceValidationLimits = .defaults
    ) throws -> URL {
        try validateReference(reference, kind: kind, limits: limits)

        let canonicalRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        var traversedURL = canonicalRoot
        for component in reference.path.replacing("\\", with: "/").split(separator: "/") {
            traversedURL.append(path: String(component))
            if (try? traversedURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw WorkspaceValidationError.pathEscapesWorkspace(reference.path)
            }
        }
        let candidate = canonicalRoot
            .appending(path: reference.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw WorkspaceValidationError.pathEscapesWorkspace(reference.path)
        }
        return candidate
    }

    private static func validate(
        _ references: [WorkspaceResourceReference],
        kind: WorkspaceResourceKind,
        limits: WorkspaceValidationLimits,
        seenPaths: inout Set<String>
    ) throws {
        var seenIdentifiers: Set<String> = []
        for reference in references {
            try validateReference(reference, kind: kind, limits: limits)
            guard seenIdentifiers.insert(reference.identifier).inserted else {
                throw WorkspaceValidationError.duplicateIdentifier(reference.identifier, kind: kind)
            }
            let normalizedPath = reference.path.replacing("\\", with: "/").lowercased()
            guard seenPaths.insert(normalizedPath).inserted else {
                throw WorkspaceValidationError.duplicatePath(reference.path)
            }
        }
    }

    private static func validateReference(
        _ reference: WorkspaceResourceReference,
        kind: WorkspaceResourceKind,
        limits: WorkspaceValidationLimits
    ) throws {
        guard !reference.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceValidationError.emptyResourceIdentifier(kind: kind)
        }
        guard !reference.path.isEmpty else { throw WorkspaceValidationError.emptyPath(kind: kind) }
        guard reference.path.utf8.count <= limits.maximumPathBytes else {
            throw WorkspaceValidationError.pathTooLong(reference.path, limit: limits.maximumPathBytes)
        }
        guard !reference.path.contains("\0") else {
            throw WorkspaceValidationError.invalidPath(reference.path)
        }

        let normalized = reference.path.replacing("\\", with: "/")
        let isWindowsAbsolute = normalized.count >= 2 && normalized[normalized.index(after: normalized.startIndex)] == ":"
        guard !normalized.hasPrefix("/"), !normalized.hasPrefix("//"), !isWindowsAbsolute else {
            throw WorkspaceValidationError.absolutePath(reference.path)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WorkspaceValidationError.pathEscapesWorkspace(reference.path)
        }
        guard components.first == Substring(kind.rawValue) else {
            throw WorkspaceValidationError.wrongResourceDirectory(path: reference.path, expected: kind.rawValue)
        }

        let pathExtension = URL(filePath: normalized).pathExtension.lowercased()
        guard kind.allowedPathExtensions.contains(pathExtension) else {
            throw WorkspaceValidationError.invalidPathExtension(path: reference.path, kind: kind)
        }
    }
}

enum WorkspaceValidationError: Error, Equatable {
    case manifestTooLarge(limit: Int)
    case unsupportedSchemaVersion(Int)
    case emptyManifestIdentifier
    case emptyDisplayName
    case tooManyReferences(limit: Int)
    case emptyResourceIdentifier(kind: WorkspaceResourceKind)
    case duplicateIdentifier(String, kind: WorkspaceResourceKind)
    case duplicatePath(String)
    case emptyPath(kind: WorkspaceResourceKind)
    case pathTooLong(String, limit: Int)
    case invalidPath(String)
    case absolutePath(String)
    case pathEscapesWorkspace(String)
    case wrongResourceDirectory(path: String, expected: String)
    case invalidPathExtension(path: String, kind: WorkspaceResourceKind)
}
