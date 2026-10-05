import Foundation
import Testing
@testable import FRTMProxy

@Suite("Proxy lifecycle safety")
struct ProxyLifecycleTests {
    @Test func upstreamTrustIsEnabled() {
        let arguments = MitmproxyService.buildArguments(
            scriptURL: URL(fileURLWithPath: "/tmp/bridge.py"),
            selectedPort: 8080,
            restrictToHosts: false,
            hosts: []
        )
        #expect(arguments.contains("ssl_insecure=false"))
        #expect(!arguments.contains("ssl_insecure=true"))
    }

    @Test func ownershipRequiresTheExactEndpoint() {
        let owned = MacOSProxySnapshot.ProxySettings(enabled: true, host: "localhost", port: 8080)
        #expect(MacOSProxyOverrideManager.owns(owned, override: owned))
        #expect(!MacOSProxyOverrideManager.owns(.init(enabled: true, host: "localhost", port: 9090), override: owned))
        #expect(!MacOSProxyOverrideManager.owns(.init(enabled: true, host: "corp.example", port: 8080), override: owned))
        #expect(!MacOSProxyOverrideManager.owns(.init(enabled: false, host: "localhost", port: 8080), override: owned))
    }

    @Test func rollbackAndExternalChangesWithoutTouchingRealNetworkSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let journal = directory.appending(path: "proxy.json")
        let suiteName = "ProxyLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let fixture = NetworkSettingsFixture()
        let manager = MacOSProxyOverrideManager(defaults: defaults, journalURL: journal, commandRunner: { try fixture.run($0) })
        try await manager.enableProxy(host: "localhost", port: 8080)
        #expect(FileManager.default.fileExists(atPath: journal.path))
        fixture.setSecureProxy(host: "corporate.example", port: 3128)
        try await manager.disableProxy()
        #expect(!fixture.http.enabled)
        #expect(fixture.https.host == "corporate.example")
        #expect(!FileManager.default.fileExists(atPath: journal.path))

        fixture.failNextSecureWrite()
        await #expect(throws: (any Error).self) {
            try await manager.enableProxy(host: "localhost", port: 8080)
        }
        #expect(!fixture.http.enabled)
        #expect(fixture.https.host == "corporate.example")
        #expect(!FileManager.default.fileExists(atPath: journal.path))

        try await manager.enableProxy(host: "localhost", port: 8080)
        try await manager.enableProxy(host: "localhost", port: 9090)
        #expect(fixture.http.port == 9090)
        #expect(fixture.https.port == 9090)
        try await manager.disableProxy()
        #expect(!fixture.http.enabled)
        #expect(fixture.https.host == "corporate.example")
    }
}

private final class NetworkSettingsFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool: MacOSProxySnapshot.ProxySettings] = [
        false: .init(enabled: false, host: "old.example", port: 8888),
        true: .init(enabled: false, host: "old.example", port: 8888)
    ]
    private var failSecure = false

    var http: MacOSProxySnapshot.ProxySettings { lock.lock(); defer { lock.unlock() }; return values[false] ?? .init(enabled: false, host: nil, port: nil) }
    var https: MacOSProxySnapshot.ProxySettings { lock.lock(); defer { lock.unlock() }; return values[true] ?? .init(enabled: false, host: nil, port: nil) }

    func setSecureProxy(host: String, port: Int) {
        lock.lock(); defer { lock.unlock() }
        values[true] = .init(enabled: true, host: host, port: port)
    }

    func failNextSecureWrite() { lock.lock(); failSecure = true; lock.unlock() }

    func run(_ arguments: [String]) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let command = arguments.first else { throw CocoaError(.fileReadCorruptFile) }
        if command == "-listallnetworkservices" { return "An asterisk denotes a disabled network service.\nWi-Fi\n" }
        let secure = command.contains("secure")
        let current = values[secure] ?? .init(enabled: false, host: nil, port: nil)
        if command.hasPrefix("-get") {
            return "Enabled: \(current.enabled ? "Yes" : "No")\nServer: \(current.host ?? "")\nPort: \(current.port ?? 0)\n"
        }
        if secure && failSecure {
            failSecure = false
            throw CocoaError(.fileWriteNoPermission)
        }
        if command.hasSuffix("state") {
            values[secure] = .init(enabled: arguments[2] == "on", host: current.host, port: current.port)
        } else {
            values[secure] = .init(enabled: current.enabled, host: arguments[2], port: Int(arguments[3]))
        }
        return ""
    }
}
