import Foundation

struct GitCollectionsSyncResult: Sendable, Hashable {
    var commit: String
    var collections: [MapCollection]
    var syncedAt: Date
}

enum GitCollectionsSyncer {
    static func sync(source: GitCollectionSource, cloneDirectory: URL) async throws -> GitCollectionsSyncResult {
        try await Task.detached(priority: .utility) {
            let remoteURL = source.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else {
                throw GitCollectionsSyncerError.invalidRemoteURL
            }

            let reference = source.reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty else {
                throw GitCollectionsSyncerError.invalidReference
            }

            try ensureGitAvailable()
            var remoteCandidates = remoteCandidates(for: remoteURL)

            if FileManager.default.fileExists(atPath: cloneDirectory.appendingPathComponent(".git").path) {
                if let origin = (try? git(["config", "--get", "remote.origin.url"], cwd: cloneDirectory, remoteURLForCredentialHelper: nil))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !origin.isEmpty,
                    !remoteCandidates.contains(origin) {
                    remoteCandidates.insert(origin, at: 0)
                }
            } else if FileManager.default.fileExists(atPath: cloneDirectory.path) {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: cloneDirectory.path)) ?? []
                if !items.isEmpty {
                    throw GitCollectionsSyncerError.cloneDirectoryNotEmpty
                }
            }

            if let clonedWith = try ensureClone(remoteCandidates: remoteCandidates, cloneDirectory: cloneDirectory) {
                remoteCandidates.removeAll(where: { $0 == clonedWith })
                remoteCandidates.insert(clonedWith, at: 0)
            }

            let effectiveRemote = try configureRemoteAndFetch(remoteCandidates: remoteCandidates, cloneDirectory: cloneDirectory)
            try checkout(reference: reference, in: cloneDirectory, remoteURLForCredentialHelper: effectiveRemote)
            let commit = try git(["rev-parse", "HEAD"], cwd: cloneDirectory).trimmingCharacters(in: .whitespacesAndNewlines)

            let scanRoot = resolveScanRoot(for: source, in: cloneDirectory)
            let collections = try loadCollectionsFromHAR(
                scanRoot: scanRoot,
                source: source,
                commit: commit
            )

            return GitCollectionsSyncResult(commit: commit, collections: collections, syncedAt: Date())
        }.value
    }

    private static func remoteCandidates(for remoteURL: String) -> [String] {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = [trimmed]
        if let ssh = sshRemoteFallback(from: trimmed), ssh != trimmed {
            result.append(ssh)
        }
        return result
    }

    private static func sshRemoteFallback(from remoteURL: String) -> String? {
        guard let url = URL(string: remoteURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host else {
            return nil
        }

        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        if !path.lowercased().hasSuffix(".git") {
            path += ".git"
        }
        return "git@\(host):\(path)"
    }

    private static func ensureClone(remoteCandidates: [String], cloneDirectory: URL) throws -> String? {
        if FileManager.default.fileExists(atPath: cloneDirectory.appendingPathComponent(".git").path) {
            return nil
        }

        var lastError: Error?
        for (index, candidate) in remoteCandidates.enumerated() {
            do {
                try git(["clone", candidate, cloneDirectory.path], cwd: nil, remoteURLForCredentialHelper: candidate)
                return candidate
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: cloneDirectory)
                if index < remoteCandidates.count - 1, shouldTryRemoteFallback(error: error) {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? GitCollectionsSyncerError.invalidRemoteURL
    }

    private static func configureRemoteAndFetch(remoteCandidates: [String], cloneDirectory: URL) throws -> String {
        var lastError: Error?
        for (index, candidate) in remoteCandidates.enumerated() {
            do {
                try git(["remote", "set-url", "origin", candidate], cwd: cloneDirectory, remoteURLForCredentialHelper: candidate)
                try git(["fetch", "--prune", "--tags"], cwd: cloneDirectory, remoteURLForCredentialHelper: candidate)
                return candidate
            } catch {
                lastError = error
                if index < remoteCandidates.count - 1, shouldTryRemoteFallback(error: error) {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? GitCollectionsSyncerError.invalidRemoteURL
    }

    private static func ensureGitAvailable() throws {
        let gitURL = URL(fileURLWithPath: "/usr/bin/git")
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            throw GitCollectionsSyncerError.gitNotAvailable
        }
    }

    private static func resolveScanRoot(for source: GitCollectionSource, in cloneDirectory: URL) -> URL {
        let trimmed = source.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { return cloneDirectory }
        return cloneDirectory.appending(path: cleaned)
    }

    private static func checkout(reference: String, in cloneDirectory: URL, remoteURLForCredentialHelper: String) throws {
        try git(["fetch", "--prune", "--tags"], cwd: cloneDirectory, remoteURLForCredentialHelper: remoteURLForCredentialHelper)

        do {
            try git(["checkout", "-B", reference, "origin/\(reference)"], cwd: cloneDirectory)
        } catch {
            try git(["checkout", reference], cwd: cloneDirectory)
        }

        if let originCommit = try? git(["rev-parse", "--verify", "origin/\(reference)^{commit}"], cwd: cloneDirectory) {
            let trimmed = originCommit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = try git(["reset", "--hard", "origin/\(reference)"], cwd: cloneDirectory)
            }
        }
    }

    private static func loadCollectionsFromHAR(scanRoot: URL, source: GitCollectionSource, commit: String) throws -> [MapCollection] {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scanRoot.path, isDirectory: &isDirectory) else {
            throw GitCollectionsSyncerError.scanPathMissing
        }

        if !isDirectory.boolValue, scanRoot.pathExtension.lowercased() == "har" {
            return [try loadCollection(fromHARFile: scanRoot, source: source, commit: commit, relativeTo: scanRoot.deletingLastPathComponent())]
        }

        guard isDirectory.boolValue else {
            throw GitCollectionsSyncerError.scanPathNotDirectory
        }

        var collections: [MapCollection] = []
        let enumerator = fileManager.enumerator(at: scanRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if url.pathComponents.contains(".git") {
                enumerator?.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "har" else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            collections.append(try loadCollection(fromHARFile: url, source: source, commit: commit, relativeTo: scanRoot))
        }

        return collections.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private static func loadCollection(fromHARFile fileURL: URL, source: GitCollectionSource, commit: String, relativeTo root: URL) throws -> MapCollection {
        let data = try Data(contentsOf: fileURL)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let createdAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        var collection = try HARCollectionConverter.importCollection(from: data, name: name, createdAt: createdAt)
        let relativePath = fileURL.path
            .replacingOccurrences(of: root.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        collection.origin = MapCollectionOrigin(
            git: GitCollectionOrigin(
                sourceID: source.id,
                remoteURL: source.remoteURL,
                reference: source.reference,
                relativePath: relativePath,
                commit: commit
            )
        )
        return collection
    }

    private static func shouldTryRemoteFallback(error: Error) -> Bool {
        if case GitCollectionsSyncerError.gitFailed(_, let output) = error {
            return isAuthenticationFailure(output)
        }
        return false
    }

    private static func isAuthenticationFailure(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("authentication failed")
            || lowered.contains("terminal prompts disabled")
            || lowered.contains("could not read username")
            || lowered.contains("could not read password")
            || lowered.contains("the requested url returned error: 401")
            || lowered.contains("the requested url returned error: 403")
            || lowered.contains("repository not found")
            || lowered.contains("access denied")
    }

    private static func gitCredentialHelperArgs(for remoteURL: String?) -> [String] {
        guard let remoteURL,
              let url = URL(string: remoteURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return []
        }

        let helper = URL(fileURLWithPath: "/usr/bin/git-credential-osxkeychain")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return []
        }

        return ["-c", "credential.helper=osxkeychain"]
    }

    private static func git(_ args: [String], cwd: URL?, remoteURLForCredentialHelper: String? = nil) throws -> String {
        let fullArgs = gitCredentialHelperArgs(for: remoteURLForCredentialHelper) + args

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = fullArgs
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        if environment["HOME"] == nil {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if environment["PATH"] == nil {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitCollectionsSyncerError.gitFailed(args: fullArgs, output: error.localizedDescription)
        }

        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let combined = [outData, errData]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined()

        guard process.terminationStatus == 0 else {
            throw GitCollectionsSyncerError.gitFailed(args: fullArgs, output: combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return combined
    }
}

enum GitCollectionsSyncerError: LocalizedError {
    case invalidRemoteURL
    case invalidReference
    case gitNotAvailable
    case cloneDirectoryNotEmpty
    case scanPathMissing
    case scanPathNotDirectory
    case gitFailed(args: [String], output: String)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL:
            return "Git remote URL non valido."
        case .invalidReference:
            return "Git branch/tag/commit non valido."
        case .gitNotAvailable:
            return "git non disponibile (atteso in /usr/bin/git)."
        case .cloneDirectoryNotEmpty:
            return "La cartella di clone esiste ma non è vuota."
        case .scanPathMissing:
            return "Il percorso di scansione non esiste nel repository."
        case .scanPathNotDirectory:
            return "Il percorso di scansione non è una directory."
        case .gitFailed(let args, let output):
            let renderedArgs = args.joined(separator: " ")
            if output.isEmpty {
                return "git fallito: \(renderedArgs)"
            }
            return "git fallito: \(renderedArgs)\n\n\(output)"
        }
    }
}
