import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace bundle service round trip")
struct WorkspaceServiceRoundTripTests {
    @Test("Export creates a Git-native directory that imports losslessly")
    func exportImportRoundTrip() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceBundleService()
        let expected = WorkspaceServiceTestSupport.bundle()

        let workspaceURL = try await service.export(
            expected,
            toSelectedRoot: root,
            directoryName: "api.frtm"
        )
        let imported = try await service.importWorkspace(from: workspaceURL)

        #expect(imported == expected)
        #expect(FileManager.default.fileExists(
            atPath: workspaceURL.appending(path: WorkspaceFormat.manifestFilename).path
        ))
        #expect(FileManager.default.fileExists(atPath: workspaceURL.appending(path: "rules/rule.json").path))
        #expect(FileManager.default.fileExists(atPath: workspaceURL.appending(path: "scripts/transform.js").path))
    }

    @Test("Export rejects missing and unexpected payloads")
    func payloadSetMustMatchManifest() async throws {
        let root = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceBundleService()
        let valid = WorkspaceServiceTestSupport.bundle()
        let missing = WorkspaceBundle(manifest: valid.manifest, resources: [valid.resources[0]])

        await #expect(throws: WorkspaceServiceError.self) {
            try await service.export(missing, toSelectedRoot: root)
        }

        let extraReference = WorkspaceResourceReference(identifier: "extra", path: "rules/extra.json")
        let unexpected = WorkspaceBundle(
            manifest: valid.manifest,
            resources: valid.resources + [
                .init(kind: .rule, reference: extraReference, data: Data("{}".utf8))
            ]
        )
        await #expect(throws: WorkspaceServiceError.self) {
            try await service.export(unexpected, toSelectedRoot: root)
        }
    }
}
