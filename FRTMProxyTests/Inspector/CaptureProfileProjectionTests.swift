import Foundation
import Testing
@testable import FRTMProxy

@Suite("Capture profile inspector projection")
struct CaptureProfileProjectionTests {
    @Test func profileMembershipOverridesOldPinsAndKeepsExplicitSearchAndStatus() async throws {
        let flows = [
            flow(id: "host", host: "api.intesa.example", app: "com.other", method: "GET", status: 200),
            flow(id: "app", host: "unrelated.example", app: "com.intesa.mobile", method: "GET", status: 503),
            flow(id: "both", host: "api.intesa.example", app: "com.intesa.mobile", method: "POST", status: 500),
            flow(id: "old-pin", host: "old.example", app: "com.old", method: "GET", status: 500)
        ]
        let profile = CaptureProfile(name: "Intesa", members: [.host("api.intesa.example"), .app("com.intesa.mobile")])
        var filter = FlowFilter()
        filter.updateActivePinnedHosts(["old.example"])
        filter.updateActivePinnedApps(["com.old"])
        let worker = InspectorFlowFilterWorker()

        let profileRows = try await worker.project(flows: flows, filter: filter, profile: profile)
        // Host and app members are alternatives, even when both old pin filters disagree.
        #expect(profileRows.flows.map(\.id) == ["host", "app", "both"])
        #expect(filter.activePinnedHosts == ["old.example"])
        #expect(filter.activePinnedApps == ["com.old"])

        filter.searchText = "method:GET status:5xx"
        let searched = try await worker.project(flows: flows, filter: filter, profile: profile)
        #expect(searched.flows.map(\.id) == ["app"])

        filter.searchText = ""
        filter.showErrorsOnly = true
        let errors = try await worker.project(flows: flows, filter: filter, profile: profile)
        #expect(errors.flows.map(\.id) == ["app", "both"])

        filter.showErrorsOnly = false
        let withoutProfile = try await worker.project(flows: flows, filter: filter)
        #expect(withoutProfile.flows.map(\.id) == ["old-pin"])
    }

    @Test func membershipIndexRefreshesForEditsAndPreservesLegacyOR() async throws {
        let flows = [
            flow(id: "host", host: "api.intesa.example", app: "com.other", method: "GET", status: 200),
            flow(id: "app", host: "unrelated.example", app: "com.intesa.mobile", method: "POST", status: 503)
        ]
        var profile = CaptureProfile(name: "Intesa", members: [.host("API.INTESA.EXAMPLE")])
        let worker = InspectorFlowFilterWorker()
        #expect(try await worker.project(flows: flows, filter: FlowFilter(), profile: profile).flows.map(\.id) == ["host"])
        profile.members = [.app(" COM.INTESA.MOBILE ")]
        #expect(try await worker.project(flows: flows, filter: FlowFilter(), profile: profile).flows.map(\.id) == ["app"])
        profile.legacyFilter = FlowFilter(searchText: "method:GET")
        #expect(try await worker.project(flows: flows, filter: FlowFilter(), profile: profile).flows.map(\.id) == ["host", "app"])
    }

    @Test func indexedProjectionMatchesReferenceFor500RowsAnd128Members() async throws {
        let flows = (0..<500).map { index in
            flow(id: String(index), host: "host\(index % 250).example", app: index.isMultiple(of: 3) ? "com.intesa.mobile" : "com.other", method: "GET", status: 200)
        }
        let members = (0..<127).map { CaptureProfileMember.host("host\($0).example") } + [.app("com.intesa.mobile")]
        let profile = CaptureProfile(name: "Intesa", members: members)
        let clock = ContinuousClock()
        var expected: [String] = []
        let referenceDuration = clock.measure {
            expected = flows.filter { profile.matches($0) }.map(\.id)
        }
        let worker = InspectorFlowFilterWorker()
        var actual: [String] = []
        let indexedDuration = try await clock.measure {
            actual = try await worker.project(flows: flows, filter: FlowFilter(), profile: profile).flows.map(\.id)
        }
        #expect(actual == expected)
        // A measured comparison, without machine-dependent timing assertions.
        print("Capture profile 500 rows / 128 members: reference=\(referenceDuration), indexed=\(indexedDuration)")
    }

    private func flow(id: String, host: String, app: String, method: String, status: Int) -> MitmFlow {
        var flow = MitmFlow(id: id, event: "response")
        flow.request = .init(method: method, url: "https://\(host)/\(id)", headers: [:], body: nil)
        flow.response = .init(status: status, headers: [:], body: nil)
        flow.clientApp = .init(id: app, displayName: app)
        return flow
    }
}
