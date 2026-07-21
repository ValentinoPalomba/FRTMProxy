import Foundation
import Testing
@testable import FRTMProxy

@Suite("Traffic rule legacy migration")
struct TrafficRuleStoreTests {
    @Test("Imports all legacy stores without changing them")
    func copyOnReadMigration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let mapData = Data(#"[{"key":"api.example.com/users","host":"api.example.com","path":"/users","scheme":"https","request":{"method":"POST","url":"https://api.example.com/users?b=2&a=1","headers":{"Content-Type":"application/json"},"body":"{\"b\":2,\"a\":1}"},"body":"{\"ok\":true}","status":201,"headers":{"Content-Type":"application/json"},"isEnabled":true}]"#.utf8)
        let breakpointData = Data(#"[{"key":"api.example.com/orders","host":"api.example.com","path":"/orders","scheme":"https","interceptRequest":true,"interceptResponse":false,"isEnabled":true}]"#.utf8)
        let scriptID = UUID()
        let scriptData = Data("""
        [{"id":"\(scriptID.uuidString)","name":"Transform","host":"example.com","path":"/v1","code":"function transform(flow) { return null; }","isEnabled":true}]
        """.utf8)

        let mapURL = directory.appending(path: "rules.json")
        let breakpointURL = directory.appending(path: "breakpoints.json")
        let scriptURL = directory.appending(path: "scripts.json")
        try mapData.write(to: mapURL)
        try breakpointData.write(to: breakpointURL)
        try scriptData.write(to: scriptURL)

        let store = TrafficRuleStore(directoryURL: directory)
        let rules = try store.loadRules()

        #expect(rules.count == 3)
        #expect(rules.map(\.priority) == [0, 1, 2])
        #expect(rules[2].id == scriptID)
        #expect(try Data(contentsOf: mapURL) == mapData)
        #expect(try Data(contentsOf: breakpointURL) == breakpointData)
        #expect(try Data(contentsOf: scriptURL) == scriptData)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "traffic-rules.json").path))

        guard case .mock = rules[0].actions.first else {
            Issue.record("Expected migrated Map Local action")
            return
        }
        guard case .breakpoint = rules[1].actions.first else {
            Issue.record("Expected migrated breakpoint action")
            return
        }
        guard case .script(let script) = rules[2].actions.first else {
            Issue.record("Expected migrated script action")
            return
        }
        #expect(script.responseOnly)
    }

    @Test("A malformed legacy file is left untouched and no partial document is written")
    func malformedLegacyIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidData = Data("not-json".utf8)
        let legacyURL = directory.appending(path: "rules.json")
        try invalidData.write(to: legacyURL)
        let store = TrafficRuleStore(directoryURL: directory)

        #expect(throws: TrafficRuleStore.StoreError.self) {
            _ = try store.loadRules()
        }
        #expect(try Data(contentsOf: legacyURL) == invalidData)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "traffic-rules.json").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "TrafficRuleStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
