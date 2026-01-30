import Foundation

struct GitCommitIdentity: Sendable, Hashable {
    var name: String
    var email: String
}

struct GitCollectionsPublishResult: Sendable, Hashable {
    var commit: String
    var pushedAt: Date
    var tag: String?
}

enum GitCollectionsPublisher {
    static func pushCollection(
        _ collection: MapCollection,
        source: GitCollectionSource,
        branch: String,
        relativePath: String,
        commitMessage: String,
        tagName: String?,
        author: GitCommitIdentity,
        cloneDirectory: URL
    ) async throws -> GitCollectionsPublishResult {
        try await Task.detached(priority: .utility) {
            let remoteURL = source.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else {
                throw GitCollectionsPublisherError.invalidRemoteURL
            }

            let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidRefName(trimmedBranch) else {
                throw GitCollectionsPublisherError.invalidBranch
            }

            let validatedPath = try validateRelativePath(relativePath)

            let trimmedMessage = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmedMessage.isEmpty ? "Update collection \(collection.name)" : trimmedMessage

            let trimmedTag = tagName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tag = trimmedTag.isEmpty ? nil : trimmedTag
            if let tag, !isValidRefName(tag) {
                throw GitCollectionsPublisherError.invalidTag
            }

            try ensureGitAvailable()
            var remoteCandidates = remoteCandidates(for: remoteURL)
            if FileManager.default.fileExists(atPath: cloneDirectory.appendingPathComponent(".git").path) {
                if let origin = (try? git(["config", "--get", "remote.origin.url"], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: nil))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !origin.isEmpty,
                    !remoteCandidates.contains(origin) {
                    remoteCandidates.insert(origin, at: 0)
                }
            }

            if let clonedWith = try ensureClone(remoteCandidates: remoteCandidates, cloneDirectory: cloneDirectory) {
                remoteCandidates.removeAll(where: { $0 == clonedWith })
                remoteCandidates.insert(clonedWith, at: 0)
            }

            let effectiveRemote = try configureRemoteAndFetch(
                remoteCandidates: remoteCandidates,
                cloneDirectory: cloneDirectory,
                author: author
            )

            try checkoutBranch(trimmedBranch, in: cloneDirectory, author: author)
            try ensureCleanWorkingTree(in: cloneDirectory, author: author)

            let base = resolveRelativeBase(for: source, in: cloneDirectory)
            let fileURL = base.appending(path: validatedPath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let har = HARCollectionConverter.exportHAR(collection: collection)
            let harData = try HARCollectionConverter.harEncoder(prettyPrinted: true).encode(har)
            try harData.write(to: fileURL, options: .atomic)

            let fileRepoRelative = repoRelativePath(for: fileURL, repoRoot: cloneDirectory)
            _ = try git(["add", "--", fileRepoRelative], cwd: cloneDirectory, author: author)

            if (try git(["status", "--porcelain"], cwd: cloneDirectory, author: author))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
                throw GitCollectionsPublisherError.nothingToCommit
            }

            _ = try git(["commit", "-m", message], cwd: cloneDirectory, author: author)
            let commit = try git(["rev-parse", "HEAD"], cwd: cloneDirectory, author: author).trimmingCharacters(in: .whitespacesAndNewlines)

            var pushCandidates = remoteCandidates
            pushCandidates.removeAll(where: { $0 == effectiveRemote })
            pushCandidates.insert(effectiveRemote, at: 0)
            let pushedRemote = try pushCurrentBranch(
                trimmedBranch,
                remoteCandidates: pushCandidates,
                cloneDirectory: cloneDirectory,
                author: author
            )

            if let tag {
                try ensureTagDoesNotExist(tag, in: cloneDirectory, author: author)
                _ = try git(["tag", "-a", tag, "-m", "FRTMProxy publish \(tag)"], cwd: cloneDirectory, author: author)
                _ = try git(["push", "origin", tag], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: pushedRemote)
            }

            return GitCollectionsPublishResult(commit: commit, pushedAt: Date(), tag: tag)
        }.value
    }

    private static func ensureGitAvailable() throws {
        let gitURL = URL(fileURLWithPath: "/usr/bin/git")
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            throw GitCollectionsPublisherError.gitNotAvailable
        }
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

    private static func configureRemoteAndFetch(
        remoteCandidates: [String],
        cloneDirectory: URL,
        author: GitCommitIdentity
    ) throws -> String {
        var lastError: Error?
        for (index, candidate) in remoteCandidates.enumerated() {
            do {
                _ = try git(["remote", "set-url", "origin", candidate], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: candidate)
                _ = try git(["fetch", "--prune", "--tags"], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: candidate)
                return candidate
            } catch {
                lastError = error
                if index < remoteCandidates.count - 1, shouldTryRemoteFallback(error: error) {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? GitCollectionsPublisherError.invalidRemoteURL
    }

    private static func ensureClone(remoteCandidates: [String], cloneDirectory: URL) throws -> String? {
        if FileManager.default.fileExists(atPath: cloneDirectory.appendingPathComponent(".git").path) {
            return nil
        }

        if FileManager.default.fileExists(atPath: cloneDirectory.path) {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: cloneDirectory.path)) ?? []
            if !items.isEmpty {
                throw GitCollectionsPublisherError.cloneDirectoryNotEmpty
            }
        }

        var lastError: Error?
        for (index, candidate) in remoteCandidates.enumerated() {
            do {
                try git(["clone", candidate, cloneDirectory.path], cwd: nil, author: nil, remoteURLForCredentialHelper: candidate)
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
        throw lastError ?? GitCollectionsPublisherError.invalidRemoteURL
    }

    private static func checkoutBranch(_ branch: String, in cloneDirectory: URL, author: GitCommitIdentity) throws {
        if let originCommit = try? git(["rev-parse", "--verify", "origin/\(branch)^{commit}"], cwd: cloneDirectory, author: author) {
            let trimmed = originCommit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = try git(["checkout", "-B", branch, "origin/\(branch)"], cwd: cloneDirectory, author: author)
                _ = try git(["reset", "--hard", "origin/\(branch)"], cwd: cloneDirectory, author: author)
                return
            }
        }
        do {
            _ = try git(["checkout", "-B", branch, "origin/HEAD"], cwd: cloneDirectory, author: author)
        } catch {
            _ = try git(["checkout", "-B", branch], cwd: cloneDirectory, author: author)
        }
    }

    private static func ensureCleanWorkingTree(in cloneDirectory: URL, author: GitCommitIdentity) throws {
        _ = try git(["reset", "--hard"], cwd: cloneDirectory, author: author)
        _ = try git(["clean", "-fd"], cwd: cloneDirectory, author: author)
    }

    private static func resolveRelativeBase(for source: GitCollectionSource, in cloneDirectory: URL) -> URL {
        let trimmed = source.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { return cloneDirectory }
        let scanRoot = cloneDirectory.appending(path: cleaned)
        if scanRoot.pathExtension.lowercased() == "har" {
            return scanRoot.deletingLastPathComponent()
        }
        return scanRoot
    }

    private static func repoRelativePath(for fileURL: URL, repoRoot: URL) -> String {
        var path = fileURL.path
        if path.hasPrefix(repoRoot.path) {
            path = path.replacingOccurrences(of: repoRoot.path, with: "")
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func validateRelativePath(_ relativePath: String) throws -> String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitCollectionsPublisherError.invalidRelativePath }
        guard !trimmed.hasPrefix("/") else { throw GitCollectionsPublisherError.invalidRelativePath }

        let components = trimmed.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw GitCollectionsPublisherError.invalidRelativePath
        }
        guard !components.contains(where: { $0 == ".git" }) else {
            throw GitCollectionsPublisherError.invalidRelativePath
        }

        let normalized = components.joined(separator: "/")
        if normalized.lowercased().hasSuffix(".har") {
            return normalized
        }
        return normalized + ".har"
    }

    private static func isValidRefName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(where: \.isWhitespace) else { return false }
        guard !trimmed.hasPrefix("-") else { return false }
        return true
    }

    private static func ensureTagDoesNotExist(_ tag: String, in cloneDirectory: URL, author: GitCommitIdentity) throws {
        if (try? git(["rev-parse", "--verify", "refs/tags/\(tag)"], cwd: cloneDirectory, author: author)) != nil {
            throw GitCollectionsPublisherError.tagAlreadyExists
        }
    }

    private static func pushCurrentBranch(
        _ branch: String,
        remoteCandidates: [String],
        cloneDirectory: URL,
        author: GitCommitIdentity
    ) throws -> String {
        var lastError: Error?
        for (index, candidate) in remoteCandidates.enumerated() {
            do {
                _ = try git(["remote", "set-url", "origin", candidate], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: candidate)
                _ = try git(["push", "--set-upstream", "origin", branch], cwd: cloneDirectory, author: author, remoteURLForCredentialHelper: candidate)
                return candidate
            } catch {
                lastError = error
                if index < remoteCandidates.count - 1, shouldTryRemoteFallback(error: error) {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? GitCollectionsPublisherError.invalidRemoteURL
    }

    private static func shouldTryRemoteFallback(error: Error) -> Bool {
        if case GitCollectionsPublisherError.gitFailed(_, let output) = error {
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

    private static func git(_ args: [String], cwd: URL?, author: GitCommitIdentity?, remoteURLForCredentialHelper: String? = nil) throws -> String {
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
        if let author {
            environment["GIT_AUTHOR_NAME"] = author.name
            environment["GIT_AUTHOR_EMAIL"] = author.email
            environment["GIT_COMMITTER_NAME"] = author.name
            environment["GIT_COMMITTER_EMAIL"] = author.email
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitCollectionsPublisherError.gitFailed(args: fullArgs, output: error.localizedDescription)
        }

        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let combined = [outData, errData]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined()

        guard process.terminationStatus == 0 else {
            throw GitCollectionsPublisherError.gitFailed(args: fullArgs, output: combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return combined
    }
}

enum GitCollectionsPublisherError: LocalizedError {
    case invalidRemoteURL
    case invalidBranch
    case invalidTag
    case invalidRelativePath
    case gitNotAvailable
    case cloneDirectoryNotEmpty
    case nothingToCommit
    case tagAlreadyExists
    case gitFailed(args: [String], output: String)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL:
            return "Invalid Git remote URL."
        case .invalidBranch:
            return "Invalid branch."
        case .invalidTag:
            return "Invalid tag."
        case .invalidRelativePath:
            return "Invalid file path (use a relative path, e.g. `collections/api.har`)."
        case .gitNotAvailable:
            return "git not available (expected at /usr/bin/git)."
        case .cloneDirectoryNotEmpty:
            return "The clone directory exists but is not empty."
        case .nothingToCommit:
            return "No changes to push."
        case .tagAlreadyExists:
            return "The tag already exists in the repository."
        case .gitFailed(let args, let output):
            let renderedArgs = args.joined(separator: " ")
            if output.isEmpty {
                return "git failed: \(renderedArgs)"
            }
            return "git failed: \(renderedArgs)\n\n\(output)"
        }
    }
}
