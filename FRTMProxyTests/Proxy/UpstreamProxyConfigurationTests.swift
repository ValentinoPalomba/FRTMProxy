import Foundation
import Testing
@testable import FRTMProxy

struct UpstreamProxyConfigurationTests {
    @Test func validatesOnlyEnabledConfigurations() {
        var config = UpstreamProxyConfiguration()
        config.host = ""
        #expect(config.validationError(listenPort: 8080) == nil)
        config.isEnabled = true
        #expect(config.validationError(listenPort: 8080) != nil)
        for host in ["https://proxy.example", "proxy.example:3128", "proxy.example/path", "user@proxy.example"] {
            config.host = host
            #expect(config.validationError(listenPort: 8080) != nil)
        }
        config.host = "proxy.example"
        config.port = "65536"
        #expect(config.validationError(listenPort: 8080) != nil)
        config.port = "3128"
        #expect(config.validationError(listenPort: 8080) == nil)
        config.scheme = "socks5"
        #expect(config.validationError(listenPort: 8080) != nil)
    }

    @Test func rejectsSelfProxyLoops() {
        for host in ["localhost", "127.0.0.1", "127.0.0.2", "::1", "[::1]", "0.0.0.0"] {
            var config = UpstreamProxyConfiguration()
            config.isEnabled = true
            config.host = host
            config.port = "8080"
            #expect(config.validationError(listenPort: 8080) != nil)
        }
    }

    @Test func buildsIPv6AndKeepsSecretsOutOfArguments() throws {
        var config = UpstreamProxyConfiguration()
        config.isEnabled = true
        config.scheme = "https"
        config.host = "::1"
        config.username = "alice"
        #expect(config.endpoint == "https://[::1]:7890")
        #expect(config.validationError(listenPort: 8080) == nil)
        let args = MitmproxyService.buildArguments(scriptURL: URL(filePath: "/tmp/bridge.py"),
                                                 selectedPort: 8080, restrictToHosts: false,
                                                 hosts: [], upstream: config)
        #expect(args.contains("upstream:https://[::1]:7890"))
        #expect(!args.joined().contains("alice"))
        let environment = try config.environment(password: "secret:password")
        #expect(environment["FRTMPROXY_UPSTREAM"]?.contains("alice:secret:password") == true)
        config.isEnabled = false
        #expect(try config.environment(password: "secret").isEmpty)
    }

    @Test func settingsSurviveRelaunch() throws {
        let name = "UpstreamSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.upstreamProxy.isEnabled)
        settings.upstreamProxy.isEnabled = true
        settings.upstreamProxy.host = "corp.example"
        settings.upstreamProxy.bypassHosts = "*.internal,localhost"
        let restored = SettingsStore(defaults: defaults)
        #expect(restored.upstreamProxy == settings.upstreamProxy)
    }
}
