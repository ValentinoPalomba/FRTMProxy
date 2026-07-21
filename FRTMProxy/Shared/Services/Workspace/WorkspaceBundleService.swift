import Foundation

actor WorkspaceBundleService {
    private let securityScopedAccessor: any WorkspaceSecurityScopedAccessing
    private let commitHook: any WorkspaceExportCommitting
    private let limits: WorkspaceServiceLimits

    init(
        securityScopedAccessor: any WorkspaceSecurityScopedAccessing = WorkspaceSecurityScopedURLAccessor(),
        commitHook: any WorkspaceExportCommitting = WorkspaceExportCommitHook(),
        limits: WorkspaceServiceLimits = .defaults
    ) {
        self.securityScopedAccessor = securityScopedAccessor
        self.commitHook = commitHook
        self.limits = limits
    }

    func export(
        _ bundle: WorkspaceBundle,
        toSelectedRoot selectedRoot: URL,
        directoryName: String? = nil
    ) throws -> URL {
        try limits.validate()
        return try securityScopedAccessor.withAccess(to: selectedRoot) {
            try exportWithinScope(bundle, selectedRoot: selectedRoot, directoryName: directoryName)
        }
    }

    func importWorkspace(from workspaceRoot: URL) throws -> WorkspaceBundle {
        try limits.validate()
        return try securityScopedAccessor.withAccess(to: workspaceRoot) {
            try importWithinScope(from: workspaceRoot)
        }
    }

    private func exportWithinScope(
        _ bundle: WorkspaceBundle,
        selectedRoot: URL,
        directoryName: String?
    ) throws -> URL {
        try WorkspaceImportValidator.validate(bundle.manifest, limits: limits.validation)
        let manifestData = try WorkspaceManifestCodec.encode(bundle.manifest)
        guard manifestData.count <= limits.validation.maximumManifestBytes else {
            throw WorkspaceServiceError.manifestTooLarge(limit: limits.validation.maximumManifestBytes)
        }

        let fileManager = FileManager.default
        let canonicalRoot = selectedRoot.standardizedFileURL.resolvingSymlinksInPath()
        try requireDirectory(canonicalRoot, fileManager: fileManager)

        let name = try validatedDirectoryName(directoryName ?? defaultDirectoryName(for: bundle.manifest))
        let destination = canonicalRoot.appending(path: name, directoryHint: .isDirectory)
        try requireContained(destination, in: canonicalRoot)
        try requireReplaceableDestination(destination, fileManager: fileManager)

        let payloads = try validatedPayloads(bundle)
        let staging = canonicalRoot.appending(
            path: ".frtm-workspace-\(UUID().uuidString).tmp",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        for payload in payloads {
            let target = try WorkspaceImportValidator.resolve(
                payload.reference,
                kind: payload.kind,
                inside: staging,
                limits: limits.validation
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.data.write(to: target, options: .atomic)
        }
        try manifestData.write(
            to: staging.appending(path: WorkspaceFormat.manifestFilename),
            options: .atomic
        )

        try commitHook.willCommitExport()
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return destination
    }

    private func importWithinScope(from workspaceRoot: URL) throws -> WorkspaceBundle {
        let fileManager = FileManager.default
        let canonicalRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        try requireDirectory(canonicalRoot, fileManager: fileManager)

        let manifestURL = canonicalRoot.appending(path: WorkspaceFormat.manifestFilename)
        try rejectSymbolicLinks(relativePath: WorkspaceFormat.manifestFilename, root: canonicalRoot, fileManager: fileManager)
        let manifestData = try read(
            manifestURL,
            maximumBytes: limits.validation.maximumManifestBytes,
            fileManager: fileManager
        )
        let manifest = try WorkspaceManifestCodec.decode(manifestData, limits: limits.validation)

        var resources: [WorkspaceResourcePayload] = []
        var totalBytes = 0
        for entry in resourceEntries(in: manifest) {
            try rejectSymbolicLinks(relativePath: entry.reference.path, root: canonicalRoot, fileManager: fileManager)
            let resourceURL = try WorkspaceImportValidator.resolve(
                entry.reference,
                kind: entry.kind,
                inside: canonicalRoot,
                limits: limits.validation
            )
            let data = try read(resourceURL, maximumBytes: limits.maximumResourceBytes, fileManager: fileManager)
            let (sum, overflow) = totalBytes.addingReportingOverflow(data.count)
            guard !overflow, sum <= limits.maximumTotalResourceBytes else {
                throw WorkspaceServiceError.totalResourcesTooLarge(limit: limits.maximumTotalResourceBytes)
            }
            totalBytes = sum
            try validateContent(data, reference: entry.reference)
            resources.append(.init(kind: entry.kind, reference: entry.reference, data: data))
        }
        return WorkspaceBundle(manifest: manifest, resources: resources)
    }

    private func validatedPayloads(_ bundle: WorkspaceBundle) throws -> [WorkspaceResourcePayload] {
        let expected = resourceEntries(in: bundle.manifest)
        let expectedByPath = Dictionary(uniqueKeysWithValues: expected.map { ($0.reference.path, $0) })
        var seenPaths: Set<String> = []
        var totalBytes = 0

        for payload in bundle.resources {
            guard seenPaths.insert(payload.reference.path).inserted else {
                throw WorkspaceServiceError.duplicatePayload(payload.reference.path)
            }
            guard let expectedEntry = expectedByPath[payload.reference.path],
                  expectedEntry.kind == payload.kind,
                  expectedEntry.reference == payload.reference else {
                throw WorkspaceServiceError.unexpectedPayload(payload.reference.path)
            }
            guard payload.data.count <= limits.maximumResourceBytes else {
                throw WorkspaceServiceError.resourceTooLarge(
                    path: payload.reference.path,
                    limit: limits.maximumResourceBytes
                )
            }
            let (sum, overflow) = totalBytes.addingReportingOverflow(payload.data.count)
            guard !overflow, sum <= limits.maximumTotalResourceBytes else {
                throw WorkspaceServiceError.totalResourcesTooLarge(limit: limits.maximumTotalResourceBytes)
            }
            totalBytes = sum
            try validateContent(payload.data, reference: payload.reference)
        }

        let missing = Set(expectedByPath.keys).subtracting(seenPaths)
        guard missing.isEmpty else {
            throw WorkspaceServiceError.missingPayload(missing.sorted().joined(separator: ", "))
        }
        return bundle.resources.sorted { $0.reference.path < $1.reference.path }
    }

    private func resourceEntries(
        in manifest: WorkspaceManifest
    ) -> [(kind: WorkspaceResourceKind, reference: WorkspaceResourceReference)] {
        manifest.resources.rules.map { (.rule, $0) }
            + manifest.resources.scripts.map { (.script, $0) }
            + manifest.resources.breakpoints.map { (.breakpoint, $0) }
            + manifest.resources.profiles.map { (.profile, $0) }
            + manifest.resources.sessions.map { (.session, $0) }
            + manifest.resources.policies.map { (.policy, $0) }
    }

    private func validateContent(_ data: Data, reference: WorkspaceResourceReference) throws {
        switch URL(filePath: reference.path).pathExtension.lowercased() {
        case "js":
            guard String(data: data, encoding: .utf8) != nil else {
                throw WorkspaceServiceError.invalidUTF8(reference.path)
            }
        case "json", "har":
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                throw WorkspaceServiceError.invalidJSON(reference.path)
            }
        default:
            throw WorkspaceServiceError.unsupportedContent(reference.path)
        }
    }

    private func read(_ url: URL, maximumBytes: Int, fileManager: FileManager) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw WorkspaceServiceError.missingFile(url)
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WorkspaceServiceError.notRegularFile(url) }
        guard let size = values.fileSize, size <= maximumBytes else {
            throw WorkspaceServiceError.fileTooLarge(url: url, limit: maximumBytes)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else {
            throw WorkspaceServiceError.fileTooLarge(url: url, limit: maximumBytes)
        }
        return data
    }

    private func rejectSymbolicLinks(relativePath: String, root: URL, fileManager: FileManager) throws {
        var current = root
        for component in relativePath.replacing("\\", with: "/").split(separator: "/") {
            current.append(path: String(component))
            guard fileManager.fileExists(atPath: current.path) else { continue }
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WorkspaceServiceError.symbolicLinkNotAllowed(current)
            }
        }
    }

    private func requireDirectory(_ url: URL, fileManager: FileManager) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw WorkspaceServiceError.notDirectory(url) }
    }

    private func requireReplaceableDestination(_ destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try requireDirectory(destination, fileManager: fileManager)
        let contents = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.isEmpty || fileManager.fileExists(
            atPath: destination.appending(path: WorkspaceFormat.manifestFilename).path
        ) else {
            throw WorkspaceServiceError.destinationContainsUnrelatedFiles(destination)
        }
    }

    private func requireContained(_ candidate: URL, in root: URL) throws {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw WorkspaceServiceError.destinationEscapesSelectedRoot(candidate)
        }
    }

    private func validatedDirectoryName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0") else {
            throw WorkspaceServiceError.invalidDirectoryName(value)
        }
        return trimmed
    }

    private func defaultDirectoryName(for manifest: WorkspaceManifest) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = manifest.identifier.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let base = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (base.isEmpty ? "workspace" : base) + ".frtm"
    }
}

enum WorkspaceServiceError: Error, LocalizedError {
    case invalidLimits
    case securityScopedAccessDenied(URL)
    case manifestTooLarge(limit: Int)
    case invalidDirectoryName(String)
    case destinationEscapesSelectedRoot(URL)
    case destinationContainsUnrelatedFiles(URL)
    case duplicatePayload(String)
    case unexpectedPayload(String)
    case missingPayload(String)
    case resourceTooLarge(path: String, limit: Int)
    case totalResourcesTooLarge(limit: Int)
    case unsupportedContent(String)
    case invalidUTF8(String)
    case invalidJSON(String)
    case missingFile(URL)
    case notRegularFile(URL)
    case notDirectory(URL)
    case fileTooLarge(url: URL, limit: Int)
    case symbolicLinkNotAllowed(URL)

    var errorDescription: String? {
        switch self {
        case .invalidLimits: "Workspace size limits are invalid."
        case let .securityScopedAccessDenied(url): "Access was denied for \(url.lastPathComponent)."
        case let .manifestTooLarge(limit): "The workspace manifest exceeds \(limit) bytes."
        case let .invalidDirectoryName(name): "Invalid workspace directory name: \(name)"
        case .destinationEscapesSelectedRoot: "The destination escapes the selected directory."
        case .destinationContainsUnrelatedFiles: "The destination contains files that are not a workspace."
        case let .duplicatePayload(path): "Duplicate workspace payload: \(path)"
        case let .unexpectedPayload(path): "Unexpected workspace payload: \(path)"
        case let .missingPayload(path): "Missing workspace payload: \(path)"
        case let .resourceTooLarge(path, limit): "\(path) exceeds the \(limit)-byte resource limit."
        case let .totalResourcesTooLarge(limit): "Workspace resources exceed \(limit) bytes."
        case let .unsupportedContent(path): "Unsupported workspace content: \(path)"
        case let .invalidUTF8(path): "JavaScript resource is not UTF-8: \(path)"
        case let .invalidJSON(path): "JSON resource is invalid: \(path)"
        case let .missingFile(url): "Workspace file is missing: \(url.lastPathComponent)"
        case let .notRegularFile(url): "Workspace resource is not a regular file: \(url.lastPathComponent)"
        case let .notDirectory(url): "Expected a directory at \(url.path)."
        case let .fileTooLarge(url, limit): "\(url.lastPathComponent) exceeds \(limit) bytes."
        case let .symbolicLinkNotAllowed(url): "Symbolic links are not allowed: \(url.lastPathComponent)"
        }
    }
}
