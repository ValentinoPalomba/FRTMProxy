import Foundation
@testable import FRTMProxy

enum WorkspaceServiceTestSupport {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "FRTMProxyWorkspaceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func bundle(ruleBody: String = "old") -> WorkspaceBundle {
        let rule = WorkspaceResourceReference(identifier: "rule", path: "rules/rule.json")
        let script = WorkspaceResourceReference(identifier: "script", path: "scripts/transform.js")
        let manifest = WorkspaceManifest(
            identifier: "api",
            displayName: "API",
            resources: WorkspaceResources(rules: [rule], scripts: [script])
        )
        return WorkspaceBundle(
            manifest: manifest,
            resources: [
                WorkspaceResourcePayload(
                    kind: .rule,
                    reference: rule,
                    data: Data("{\"body\":\"\(ruleBody)\"}".utf8)
                ),
                WorkspaceResourcePayload(
                    kind: .script,
                    reference: script,
                    data: Data("function transform(flow) { return flow; }".utf8)
                )
            ]
        )
    }
}
