import Foundation
import Testing
@testable import FRTMProxy

@Suite("Capture profiles")
@MainActor
struct CaptureProfileTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "CaptureProfileTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func flow(url: String = "https://api.intesa.example/accounts?token=secret#row", method: String = "GET", app: String? = nil) -> MitmFlow {
        var flow = MitmFlow(id: UUID().uuidString, event: "request")
        flow.request = .init(method: method, url: url, headers: [:], body: nil)
        if let app { flow.clientApp = .init(id: app, displayName: "Curl") }
        return flow
    }

    @Test func membershipUsesORWithoutLeakingQueryOrChangingPathCase() throws {
        let request = try #require(CaptureProfileMember.request(for: flow(url: "HTTPS://API.INTESA.EXAMPLE:443/Accounts?token=secret#row", method: "get")))
        #expect(request == .request(method: "GET", url: "https://api.intesa.example/Accounts"))
        let profile = CaptureProfile(name: "Intesa", members: [request, .host(" CHEBANCA.EXAMPLE "), .app(" COM.CURL ")])
        #expect(profile.matches(flow(url: "https://api.intesa.example/Accounts?other=1")))
        #expect(!profile.matches(flow(url: "https://api.intesa.example/accounts")))
        #expect(!profile.matches(flow(url: "https://api.intesa.example/Accounts", method: "POST")))
        #expect(profile.matches(flow(url: "https://chebanca.example/anything", method: "POST")))
        #expect(profile.matches(flow(url: "https://unrelated.example/", app: "com.curl")))
        #expect(!profile.matches(flow(url: "https://unrelated.example/")))
        #expect(CaptureProfileMember.request(for: flow(url: "file:///tmp/secret")) == nil)
    }

    @Test func hostAndAppValidationAcceptsNativeIdentifiersAndRejectsURLs() {
        let invalidHosts = [
            "https://api.example", "api.example/path", "api.example?token=x", "api.example#section",
            "user@api.example", "api.example:443", "two hosts", "bad\u{0000}host", "api.example\n",
            "-bad.example", "bad-.example", "bad..example", "999.1.2.3",
            String(repeating: "a", count: 64) + ".example"
        ]
        for value in invalidHosts {
            #expect(CaptureProfileMember.host(value).normalized == nil)
        }
        #expect(CaptureProfileMember.host(" LOCALHOST ").normalized == .host("localhost"))
        #expect(CaptureProfileMember.host("API.EXAMPLE.").normalized == .host("api.example"))
        #expect(CaptureProfileMember.host("127.0.0.1").normalized == .host("127.0.0.1"))
        #expect(CaptureProfileMember.host("[0:0:0:0:0:0:0:1]").normalized == .host("::1"))
        #expect(CaptureProfileMember.host("::1").matches(flow(url: "http://[::1]:8080/")))
        #expect(CaptureProfileMember.app(" Curl ").normalized == .app("curl"))
        #expect(CaptureProfileMember.app("COM.CURL").normalized == .app("com.curl"))
        for value in ["two apps", "com.\tapp", "com.\u{0000}app", "curl\n", ""] {
            #expect(CaptureProfileMember.app(value).normalized == nil)
        }
    }

    @Test func duplicateMembersSelectionRenameAndReload() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CaptureProfileStore(defaults: defaults)
        let first = try store.createProfile(name: " Intesa ", member: .host("API.EXAMPLE"))
        try store.add(member: .host(" api.example "), to: first.id)
        #expect(store.profiles.first?.members == [.host("api.example")])
        store.selectProfile(first.id)
        try store.renameProfile(first.id, name: "Intesa mobile")
        let reopened = CaptureProfileStore(defaults: defaults)
        #expect(reopened.activeProfile?.name == "Intesa mobile")
        #expect(reopened.profiles == store.profiles)
        try reopened.removeMember(.host("API.EXAMPLE"), from: first.id)
        #expect(reopened.activeProfile?.members.isEmpty == true)
        try reopened.removeProfile(first.id)
        #expect(CaptureProfileStore(defaults: defaults).activeProfileID == nil)
    }

    @Test func invalidMutationsPreserveStoredSnapshot() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CaptureProfileStore(defaults: defaults)
        let profile = try store.createProfile(name: "Curl")
        let before = defaults.data(forKey: CaptureProfileStore.dataKey)
        #expect(throws: CaptureProfileStore.Failure.self) { try store.createProfile(name: " curl ") }
        #expect(throws: CaptureProfileStore.Failure.self) { try store.renameProfile(profile.id, name: String(repeating: "é", count: 65)) }
        #expect(throws: CaptureProfileStore.Failure.self) { try store.add(member: .request(method: "GET", url: "file:///etc/passwd"), to: profile.id) }
        #expect(throws: CaptureProfileStore.Failure.self) { try store.add(member: .host("https://api.example/path"), to: profile.id) }
        #expect(throws: CaptureProfileStore.Failure.self) { try store.add(member: .app("two apps"), to: profile.id) }
        store.selectProfile(UUID())
        #expect(defaults.data(forKey: CaptureProfileStore.dataKey) == before)
        #expect(store.profiles == [profile])
        #expect(store.activeProfileID == nil)
        #expect(store.canEdit)
        #expect(store.errorMessage != nil)
    }

    @Test func boundsAreEnforcedButDuplicateAtLimitIsAllowed() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CaptureProfileStore(defaults: defaults)
        let profile = try store.createProfile(name: "Curl")
        for index in 0..<128 { try store.add(member: .host("host\(index).example"), to: profile.id) }
        try store.add(member: .host("HOST0.EXAMPLE"), to: profile.id)
        let before = defaults.data(forKey: CaptureProfileStore.dataKey)
        #expect(throws: CaptureProfileStore.Failure.self) { try store.add(member: .host("overflow.example"), to: profile.id) }
        #expect(defaults.data(forKey: CaptureProfileStore.dataKey) == before)
        for index in 1..<50 { try store.createProfile(name: "Profile \(index)") }
        #expect(throws: CaptureProfileStore.Failure.self) { try store.createProfile(name: "Overflow") }
    }

    @Test func missingStorageIsEmptyAndCorruptStorageIsNeverOverwritten() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(CaptureProfileStore(defaults: defaults).profiles.isEmpty)
        let corrupt = Data("unreadable profiles".utf8)
        defaults.set(corrupt, forKey: CaptureProfileStore.dataKey)
        let store = CaptureProfileStore(defaults: defaults)
        #expect(!store.canEdit)
        #expect(store.errorMessage != nil)
        #expect(throws: CaptureProfileStore.Failure.self) { try store.createProfile(name: "New") }
        store.selectProfile(nil)
        #expect(defaults.data(forKey: CaptureProfileStore.dataKey) == corrupt)
    }

    @Test func oversizedAndMissingSelectionStorageArePreserved() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        for data in [Data(repeating: 0, count: 256 * 1024 + 1),
                     Data("{\"profiles\":[],\"activeProfileID\":\"\(UUID().uuidString)\"}".utf8)] {
            defaults.set(data, forKey: CaptureProfileStore.dataKey)
            let store = CaptureProfileStore(defaults: defaults)
            #expect(!store.canEdit)
            #expect(throws: CaptureProfileStore.Failure.self) { try store.createProfile(name: "New") }
            #expect(defaults.data(forKey: CaptureProfileStore.dataKey) == data)
        }
    }

    @Test func legacyMigrationPreservesSourceAndFullFilterSemantics() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var filter = FlowFilter()
        filter.activePinnedHosts = ["api.intesa.example"]
        filter.searchText = "method:POST"
        let legacy = SavedFocusSet(name: "Intesa", filter: filter)
        let data = try SavedFocusSet.encode([legacy])
        defaults.set(data, forKey: SavedFocusSet.dataKey)
        let store = CaptureProfileStore(defaults: defaults)
        let profile = try #require(store.profiles.first)
        #expect(profile.id == legacy.id)
        #expect(profile.matches(flow(method: "POST")))
        #expect(!profile.matches(flow(method: "GET")))
        #expect(!profile.matches(flow(url: "https://other.example/", method: "POST")))
        try store.add(member: .app("com.curl"), to: profile.id)
        #expect(store.profiles[0].matches(flow(url: "https://other.example/", app: "com.curl")))
        #expect(defaults.data(forKey: SavedFocusSet.dataKey) == data)
        #expect(CaptureProfileStore(defaults: defaults).profiles == store.profiles)
    }
}
