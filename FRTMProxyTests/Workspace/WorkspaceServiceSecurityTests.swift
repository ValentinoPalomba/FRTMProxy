import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace bundle service security")
struct WorkspaceServiceSecurityTests {
    @Test("Export rejects traversal before creating a workspace")
    func rejectsTraversal() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = WorkspaceResourceReference(identifier: "bad", path: "rules/../outside.json")
        let bundle = WorkspaceBundle(
            manifest: WorkspaceManifest(
                identifier: "bad",
                displayName: "Bad",
                resources: WorkspaceResources(rules: [reference])
            ),
            resources: [.init(kind: .rule, reference: reference, data: Data("{}".utf8))]
        )
        let service = WorkspaceBundleService()

        await #expect(throws: WorkspaceValidationError.self) {
            try await service.export(bundle, toSelectedRoot: root)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "outside.json").path))
    }

    @Test("Import rejects resource symlinks even when their target exists")
    func rejectsSymbolicLinks() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceBundleService()
        let workspace = try await service.export(
            WorkspaceServiceTestSupport.bundle(),
            toSelectedRoot: root,
            directoryName: "api.frtm"
        )
        let outside = root.appending(path: "outside.json")
        try Data("{\"secret\":true}".utf8).write(to: outside)
        let rule = workspace.appending(path: "rules/rule.json")
        try FileManager.default.removeItem(at: rule)
        try FileManager.default.createSymbolicLink(at: rule, withDestinationURL: outside)

        await #expect(throws: WorkspaceServiceError.self) {
            try await service.importWorkspace(from: workspace)
        }
    }

    @Test("Export never replaces a non-workspace directory")
    func preservesUnrelatedDestination() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "api.frtm", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let unrelated = destination.appending(path: "notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let service = WorkspaceBundleService()

        await #expect(throws: WorkspaceServiceError.self) {
            try await service.export(
                WorkspaceServiceTestSupport.bundle(),
                toSelectedRoot: root,
                directoryName: "api.frtm"
            )
        }
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }
}
