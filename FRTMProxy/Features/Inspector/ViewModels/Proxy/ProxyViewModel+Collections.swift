import Foundation

extension ProxyViewModel {
    var isRecordingCollection: Bool {
        recordingCollectionName != nil
    }

    func startCollectionRecording(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collectionRecorder.isRecording else { return }
        collectionRecorder.start(name: trimmed)
        recordingCollectionName = trimmed
        recordingRulesPreview = []
        recordedFlowIDs = Set(flows.map { $0.id })
    }

    func stopCollectionRecording(save: Bool) {
        guard collectionRecorder.isRecording else { return }
        defer {
            recordingCollectionName = nil
            recordingRulesPreview = []
            recordedFlowIDs = []
        }
        if save, let collection = collectionRecorder.stopAndCreateCollection() {
            collections.append(collection)
            persistCollections()
            syncAppliedRules()
        } else {
            collectionRecorder.discard()
        }
    }

    func toggleCollection(_ id: UUID, enabled: Bool) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].isEnabled = enabled
        collections[index].enabledAt = enabled ? Date() : nil
        persistCollections()
        syncAppliedRules()
    }

    func renameCollection(_ id: UUID, newName: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
        persistCollections()
    }

    func deleteCollection(_ id: UUID) {
        let originalCount = collections.count
        collections.removeAll { $0.id == id }
        if originalCount != collections.count {
            persistCollections()
            syncAppliedRules()
        }
    }

    func updateRule(inCollection id: UUID, rule: MapRule) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        if let ruleIndex = collections[collectionIndex].rules.firstIndex(where: { $0.key == rule.key }) {
            collections[collectionIndex].rules[ruleIndex] = rule
        } else {
            collections[collectionIndex].rules.append(rule)
        }
        persistCollections()
        syncAppliedRules()
    }

    func deleteRule(inCollection id: UUID, ruleKey: String) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[collectionIndex].rules.removeAll { $0.key == ruleKey }
        persistCollections()
        syncAppliedRules()
    }

    func updateRecordingRule(_ rule: MapRule) {
        guard collectionRecorder.isRecording else { return }
        collectionRecorder.record(rule: rule)
        recordingRulesPreview = collectionRecorder.currentRules()
    }

    func exportCollection(_ id: UUID, to destinationURL: URL) throws {
        guard let collection = collections.first(where: { $0.id == id }) else { return }
        try collectionStore.export(collection: collection, to: destinationURL)
    }

    func importCollection(from url: URL) throws {
        let collection = try collectionStore.importCollection(at: url)
        collections.append(collection)
        persistCollections()
        syncAppliedRules()
    }

    @MainActor
    func addGitCollectionSource(remoteURL: String, reference: String, subdirectory: String?) async throws {
        let trimmedRemote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedReference.isEmpty else { return }

        let source = GitCollectionSource(remoteURL: trimmedRemote, reference: trimmedReference, subdirectory: subdirectory)
        let result = try await collectionStore.syncGitSource(source)

        var persistedSource = source
        persistedSource.lastSyncedAt = result.syncedAt
        persistedSource.lastSyncedCommit = result.commit
        gitCollectionSources.append(persistedSource)
        persistGitSources()
        applyGitCollections(result.collections)
    }

    @MainActor
    func syncGitCollectionSource(_ id: UUID) async throws {
        guard let source = gitCollectionSources.first(where: { $0.id == id }) else { return }
        let result = try await collectionStore.syncGitSource(source)
        var updated = source
        updated.lastSyncedAt = result.syncedAt
        updated.lastSyncedCommit = result.commit
        updateGitSource(updated)
        applyGitCollections(result.collections)
    }

    @MainActor
    func syncAllGitCollectionSources() async throws {
        for source in gitCollectionSources {
            let result = try await collectionStore.syncGitSource(source)
            var updated = source
            updated.lastSyncedAt = result.syncedAt
            updated.lastSyncedCommit = result.commit
            updateGitSource(updated)
            applyGitCollections(result.collections)
        }
    }

    @MainActor
    func removeGitCollectionSource(_ id: UUID) {
        gitCollectionSources.removeAll(where: { $0.id == id })
        persistGitSources()
    }

    @MainActor
    func pushCollectionToGit(
        collectionID: UUID,
        sourceID: UUID,
        branch: String,
        relativePath: String,
        commitMessage: String,
        tagName: String?,
        authorName: String?,
        authorEmail: String?
    ) async throws {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        guard let baseSource = gitCollectionSources.first(where: { $0.id == sourceID }) else { return }

        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty else { return }

        let normalizedPath = Self.normalizedHarPath(relativePath)

        let targetSource = ensureGitSourceForPush(
            baseSource: baseSource,
            branch: trimmedBranch
        )

        let identity = GitCommitIdentity(
            name: Self.normalizedGitIdentityValue(authorName, fallback: "FRTMProxy"),
            email: Self.normalizedGitIdentityValue(authorEmail, fallback: "frtmproxy@localhost")
        )

        let result = try await collectionStore.pushCollectionToGit(
            collections[collectionIndex],
            source: targetSource,
            branch: trimmedBranch,
            relativePath: normalizedPath,
            commitMessage: commitMessage,
            tagName: tagName,
            author: identity
        )

        collections[collectionIndex].origin = MapCollectionOrigin(
            git: GitCollectionOrigin(
                sourceID: targetSource.id,
                remoteURL: targetSource.remoteURL,
                reference: trimmedBranch,
                relativePath: normalizedPath,
                commit: result.commit
            )
        )
        persistCollections()

        var updatedSource = targetSource
        updatedSource.lastSyncedAt = result.pushedAt
        updatedSource.lastSyncedCommit = result.commit
        updateGitSource(updatedSource)
    }

    @MainActor
    private func updateGitSource(_ updated: GitCollectionSource) {
        guard let index = gitCollectionSources.firstIndex(where: { $0.id == updated.id }) else { return }
        gitCollectionSources[index] = updated
        persistGitSources()
    }

    @MainActor
    private func ensureGitSourceForPush(baseSource: GitCollectionSource, branch: String) -> GitCollectionSource {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBranch == baseSource.reference {
            return baseSource
        }

        if let existing = gitCollectionSources.first(where: {
            $0.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines) == baseSource.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                && ($0.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == (baseSource.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                && $0.reference.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedBranch
        }) {
            return existing
        }

        let created = GitCollectionSource(remoteURL: baseSource.remoteURL, reference: trimmedBranch, subdirectory: baseSource.subdirectory)
        gitCollectionSources.append(created)
        persistGitSources()
        return created
    }

    private static func normalizedHarPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".har") {
            return trimmed
        }
        return trimmed + ".har"
    }

    private static func normalizedGitIdentityValue(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    @MainActor
    private func applyGitCollections(_ incoming: [MapCollection]) {
        for newCollection in incoming {
            guard let newOrigin = newCollection.origin?.git else { continue }
            if let existingIndex = collections.firstIndex(where: { $0.origin?.git?.sourceID == newOrigin.sourceID && $0.origin?.git?.relativePath == newOrigin.relativePath }) {
                let preservedID = collections[existingIndex].id
                let preservedCreatedAt = collections[existingIndex].createdAt
                let preservedIsEnabled = collections[existingIndex].isEnabled
                let preservedEnabledAt = collections[existingIndex].enabledAt

                var updated = newCollection
                updated = MapCollection(
                    id: preservedID,
                    name: updated.name,
                    createdAt: preservedCreatedAt,
                    isEnabled: preservedIsEnabled,
                    enabledAt: preservedEnabledAt,
                    rules: updated.rules,
                    origin: updated.origin
                )
                collections[existingIndex] = updated
            } else {
                collections.append(newCollection)
            }
        }
        persistCollections()
        syncAppliedRules()
    }
}
