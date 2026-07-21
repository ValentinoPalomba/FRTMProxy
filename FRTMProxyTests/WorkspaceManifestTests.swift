import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace manifest")
struct WorkspaceManifestTests {
    @Test("Manifest survives a deterministic Codable round trip")
    func codableRoundTrip() throws {
        let manifest = WorkspaceManifest(
            identifier: "checkout-api",
            displayName: "Checkout API",
            summary: "Local-first traffic workspace",
            resources: WorkspaceResources(
                rules: [.init(identifier: "create-order", path: "rules/create-order.json")],
                scripts: [.init(identifier: "normalize", path: "scripts/normalize.js")],
                breakpoints: [.init(identifier: "orders", path: "breakpoints/orders.json")],
                profiles: [.init(identifier: "slow", path: "profiles/slow.json")],
                sessions: [.init(identifier: "happy-path", path: "sessions/happy-path.har")],
                policies: [.init(identifier: "default", path: "policies/redaction.json")]
            )
        )

        let first = try WorkspaceManifestCodec.encode(manifest)
        let decoded = try WorkspaceManifestCodec.decode(first)
        let second = try WorkspaceManifestCodec.encode(decoded)

        #expect(decoded == manifest)
        #expect(first == second)
    }

    @Test("Manifest and reference limits are enforced")
    func limits() throws {
        let manifest = WorkspaceManifest(
            identifier: "workspace",
            displayName: "Workspace",
            resources: WorkspaceResources(rules: [
                .init(identifier: "one", path: "rules/one.json"),
                .init(identifier: "two", path: "rules/two.json")
            ])
        )
        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceImportValidator.validate(
                manifest,
                limits: WorkspaceValidationLimits(maximumManifestBytes: 1, maximumReferences: 1, maximumPathBytes: 1_024)
            )
        }

        let data = try WorkspaceManifestCodec.encode(manifest)
        #expect(throws: WorkspaceValidationError.self) {
            try WorkspaceManifestCodec.decode(
                data,
                limits: WorkspaceValidationLimits(maximumManifestBytes: 1, maximumReferences: 10, maximumPathBytes: 1_024)
            )
        }
    }
}
