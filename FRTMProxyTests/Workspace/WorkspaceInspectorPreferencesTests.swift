import Foundation
import Testing
@testable import FRTMProxy

@Suite("Workspace inspector preferences")
struct WorkspaceInspectorPreferencesTests {
    @Test func optionalPreferencesRoundTripOnDiskAndInvalidImportsAreRejected() async throws {
        let directory = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let column = FlowHeaderColumn(phase: .response, name: "Set-Cookie")
        let preferences = WorkspaceInspectorPreferences(headerColumns: [column], headerSortID: column.id, sortAscending: false)
        let manifest = WorkspaceManifest(identifier: "columns", displayName: "Columns", inspectorPreferences: preferences)
        let bundle = WorkspaceBundle(manifest: manifest, resources: [])
        let service = WorkspaceBundleService()
        let url = try await service.export(bundle, toSelectedRoot: directory)
        #expect(try await service.importWorkspace(from: url) == bundle)
        let plan = try await service.importPlan(from: url)
        #expect(plan.resourcesToApply.isEmpty)
        #expect(plan.bundle.manifest.inspectorPreferences == preferences)
        let legacy = WorkspaceManifest(identifier: "old", displayName: "Legacy")
        #expect(try WorkspaceManifestCodec.decode(WorkspaceManifestCodec.encode(legacy)).inspectorPreferences == nil)
        var invalid = manifest
        invalid.inspectorPreferences = .init(headerColumns: [column], headerSortID: UUID())
        #expect(throws: (any Error).self) { try WorkspaceImportPlan.prepare(.init(manifest: invalid, resources: [])) }
        invalid.inspectorPreferences = .init(headerColumns: [column, column])
        #expect(throws: (any Error).self) { try WorkspaceManifestCodec.decode(WorkspaceManifestCodec.encode(invalid)) }
        let suiteName = "column-roundtrip-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try preferences.apply(to: defaults)
        let before = defaults.data(forKey: FlowHeaderColumn.dataKey)
        #expect(throws: (any Error).self) { try invalid.inspectorPreferences?.apply(to: defaults) }
        #expect(defaults.data(forKey: FlowHeaderColumn.dataKey) == before)
        try WorkspaceInspectorPreferences(headerColumns: []).apply(to: defaults)
        #expect(try WorkspaceInspectorPreferences.read(from: defaults).headerColumns.isEmpty)
        defaults.set(Data("invalid".utf8), forKey: FlowHeaderColumn.dataKey)
        #expect(throws: (any Error).self) { try WorkspaceInspectorPreferences.read(from: defaults) }
        defaults.set("wrong storage type", forKey: FlowHeaderColumn.dataKey)
        #expect(throws: (any Error).self) { try WorkspaceInspectorPreferences.read(from: defaults) }
    }
    @Test func focusAndNoiseRoundTripAndLegacyColumnsPreserveThem() async throws {
        let suiteName = "scope-workspace-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var filter = FlowFilter(searchText: "host:example.com", showMappedOnly: true, showErrorsOnly: true)
        filter.activePinnedHosts = ["example.com"]
        filter.activePinnedApps = ["com.example.app"]
        filter.activeClientIPs = ["127.0.0.1"]
        let focus = SavedFocusSet(name: "API", filter: filter)
        let preferences = WorkspaceInspectorPreferences(focusSets: [focus], noiseControl: .init(query: "host:telemetry.example", enabled: true), headerColumns: [])
        let directory = try WorkspaceServiceTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WorkspaceBundleService()
        let bundle = WorkspaceBundle(manifest: .init(identifier: "scopes", displayName: "Scopes", inspectorPreferences: preferences), resources: [])
        let url = try await service.export(bundle, toSelectedRoot: directory)
        let imported = try #require(try await service.importPlan(from: url).bundle.manifest.inspectorPreferences)
        #expect(imported == preferences)
        try imported.apply(to: defaults)
        #expect(try WorkspaceInspectorPreferences.read(from: defaults) == preferences)
        let legacyColumns = WorkspaceInspectorPreferences(headerColumns: [])
        try legacyColumns.apply(to: defaults)
        #expect(try WorkspaceInspectorPreferences.read(from: defaults) == preferences)
        var invalid = preferences
        invalid.focusSets = [SavedFocusSet(name: "", filter: filter)]
        let before = defaults.data(forKey: SavedFocusSet.dataKey)
        #expect(throws: (any Error).self) { try invalid.apply(to: defaults) }
        #expect(defaults.data(forKey: SavedFocusSet.dataKey) == before)
        invalid = preferences
        invalid.noiseControl = .init(query: String(repeating: "x", count: 4097), enabled: true)
        #expect(throws: (any Error).self) { try invalid.apply(to: defaults) }
        #expect(defaults.string(forKey: WorkspaceInspectorPreferences.NoiseControl.queryKey) == "host:telemetry.example")
        try WorkspaceInspectorPreferences(focusSets: [], headerColumns: []).apply(to: defaults)
        #expect(try WorkspaceInspectorPreferences.read(from: defaults).focusSets == [])
        defaults.set(Data("invalid".utf8), forKey: SavedFocusSet.dataKey)
        #expect(throws: (any Error).self) { try WorkspaceInspectorPreferences.read(from: defaults) }
    }
    @Test func savedFocusLimitsPreserveLegacyNamesAndRejectDuplicateIDs() throws {
        let focus = SavedFocusSet(name: "API", filter: FlowFilter(searchText: "status:500"))
        let sameLegacyName = SavedFocusSet(name: "API", filter: FlowFilter(searchText: "host:example.com"))
        #expect(try SavedFocusSet.decode(SavedFocusSet.encode([focus, sameLegacyName])) == [focus, sameLegacyName])
        #expect(throws: (any Error).self) { try SavedFocusSet.encode([focus, focus]) }
        #expect(throws: (any Error).self) { try SavedFocusSet.encode((0..<51).map { .init(name: "\($0)", filter: FlowFilter()) }) }
        #expect(throws: (any Error).self) { try SavedFocusSet.encode([.init(name: "Long", filter: FlowFilter(searchText: String(repeating: "x", count: 4097)))]) }
        #expect(throws: (any Error).self) { try SavedFocusSet.decode(Data(repeating: 32, count: 256 * 1024 + 1)) }
    }

}
