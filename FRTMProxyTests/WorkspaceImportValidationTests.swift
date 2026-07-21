import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace import validation")
struct WorkspaceImportValidationTests {
    @Test("Traversal, absolute, Windows, and wrong-root paths are rejected", arguments: [
        "rules/../secrets.json",
        "../rules/secret.json",
        "/tmp/rule.json",
        "C:\\temp\\rule.json",
        "rules\\..\\secret.json",
        "scripts/rule.json"
    ])
    func rejectsUnsafePaths(path: String) {
        let manifest = WorkspaceManifest(
            identifier: "workspace",
            displayName: "Workspace",
            resources: WorkspaceResources(rules: [.init(identifier: "rule", path: path)])
        )

        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceImportValidator.validate(manifest)
        }
    }

    @Test("Resolution remains inside the workspace and rejects symlink escapes")
    func rejectsSymlinkEscape() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workspace = temporaryRoot.appending(path: "workspace", directoryHint: .isDirectory)
        let rules = workspace.appending(path: "rules", directoryHint: .isDirectory)
        let outside = temporaryRoot.appending(path: "outside", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rules, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let link = rules.appending(path: "linked.json")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside.appending(path: "secret.json"))
        let reference = WorkspaceResourceReference(identifier: "linked", path: "rules/linked.json")

        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceImportValidator.resolve(reference, kind: .rule, inside: workspace)
        }
    }

    @Test("Valid resource paths resolve inside the workspace")
    func resolvesValidPath() throws {
        let root = URL(filePath: "/tmp/FRTMProxyWorkspace", directoryHint: .isDirectory)
        let reference = WorkspaceResourceReference(identifier: "rule", path: "rules/example.json")

        let resolved = try WorkspaceImportValidator.resolve(reference, kind: .rule, inside: root)

        #expect(resolved.path == "/tmp/FRTMProxyWorkspace/rules/example.json")
    }
}
