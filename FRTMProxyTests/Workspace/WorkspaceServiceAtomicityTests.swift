import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace bundle service atomicity")
struct WorkspaceServiceAtomicityTests {
    private struct CommitFailure: Error { }

    private struct FailingCommitHook: WorkspaceExportCommitting {
        func willCommitExport() throws {
            throw CommitFailure()
        }
    }

    @Test("A failure before commit leaves the previous workspace intact")
    func failedCommitPreservesPreviousWorkspace() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let liveService = WorkspaceBundleService()
        let oldBundle = WorkspaceServiceTestSupport.bundle(ruleBody: "old")
        let workspace = try await liveService.export(
            oldBundle,
            toSelectedRoot: root,
            directoryName: "api.frtm"
        )
        let failingService = WorkspaceBundleService(commitHook: FailingCommitHook())

        await #expect(throws: CommitFailure.self) {
            try await failingService.export(
                WorkspaceServiceTestSupport.bundle(ruleBody: "new"),
                toSelectedRoot: root,
                directoryName: "api.frtm"
            )
        }

        let imported = try await liveService.importWorkspace(from: workspace)
        #expect(imported == oldBundle)
        let temporaryEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".frtm-workspace-") }
        #expect(temporaryEntries.isEmpty)
    }

    @Test("A successful replacement publishes the complete new workspace")
    func successfulReplacement() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceBundleService()
        _ = try await service.export(
            WorkspaceServiceTestSupport.bundle(ruleBody: "old"),
            toSelectedRoot: root,
            directoryName: "api.frtm"
        )
        let expected = WorkspaceServiceTestSupport.bundle(ruleBody: "new")
        let workspace = try await service.export(
            expected,
            toSelectedRoot: root,
            directoryName: "api.frtm"
        )

        #expect(try await service.importWorkspace(from: workspace) == expected)
    }
}
