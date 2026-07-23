import Foundation
import Testing
@testable import FRTMProxy

@MainActor
@Suite("Session browser state")
struct SessionBrowserStateTests {
    @Test("Reset clears state for a new selection")
    func reset() {
        let model = SessionTimelineModel()
        let firstID = UUID()
        model.reset(for: firstID)
        model.receive(page(flows: [flow(id: "one", timestamp: 1)]), for: firstID)

        let secondID = UUID()
        model.reset(for: secondID)
        #expect(model.sessionID == secondID)
        #expect(model.flows.isEmpty)
        #expect(model.corruptFlowIDs.isEmpty)
        #expect(model.hasLoadedPage == false)
    }

    @Test("Pages append stably and replace duplicate flow metadata")
    func appendPages() {
        let model = SessionTimelineModel()
        let sessionID = UUID()
        model.reset(for: sessionID)
        let cursor = CaptureSessionPageCursor(timestamp: 1, flowID: "one")
        model.receive(
            page(flows: [flow(id: "two", timestamp: 2), flow(id: "one", timestamp: 1)], cursor: cursor),
            for: sessionID
        )
        var updatedOne = flow(id: "one", timestamp: 1)
        updatedOne.note = "Investigate"
        model.receive(page(flows: [updatedOne, flow(id: "zero", timestamp: 0)]), for: sessionID)

        #expect(model.flows.map(\.id) == ["two", "one", "zero"])
        #expect(model.flows[1].note == "Investigate")
        #expect(model.nextCursor == nil)
    }

    @Test("Stale page cannot replace current selection")
    func ignoresStalePage() {
        let model = SessionTimelineModel()
        let oldID = UUID()
        let currentID = UUID()
        model.reset(for: currentID)
        model.receive(page(flows: [flow(id: "stale", timestamp: 1)]), for: oldID)
        #expect(model.flows.isEmpty)
    }

    @Test("Corrupt flow identifiers are deduplicated")
    func corruptFlows() {
        let model = SessionTimelineModel()
        let sessionID = UUID()
        model.reset(for: sessionID)
        model.receive(page(corrupt: ["bad", "bad"]), for: sessionID)
        model.receive(page(corrupt: ["bad", "worse"]), for: sessionID)
        #expect(model.corruptFlowIDs == ["bad", "worse"])
    }

    @Test("Local metadata updates note and bookmark")
    func metadataUpdate() {
        let model = SessionTimelineModel()
        let sessionID = UUID()
        model.reset(for: sessionID)
        model.receive(page(flows: [flow(id: "one", timestamp: 1)]), for: sessionID)
        model.updateMetadata(flowID: "one", note: "Pinned", isBookmarked: true)
        #expect(model.flows.first?.note == "Pinned")
        #expect(model.flows.first?.isBookmarked == true)
    }

    @Test("Pagination failure keeps loaded rows and cursor available for retry")
    func paginationFailureRetention() {
        struct PaginationFailure: LocalizedError {
            var errorDescription: String? { "Page unavailable" }
        }

        let model = SessionTimelineModel()
        let sessionID = UUID()
        let cursor = CaptureSessionPageCursor(timestamp: 1, flowID: "one")
        model.reset(for: sessionID)
        model.receive(
            page(flows: [flow(id: "one", timestamp: 1)], cursor: cursor),
            for: sessionID
        )

        model.startLoading()
        model.fail(PaginationFailure(), for: sessionID)

        #expect(model.flows.map(\.id) == ["one"])
        #expect(model.nextCursor == cursor)
        #expect(model.canLoadMore)
        #expect(model.errorMessage == "Page unavailable")
    }

    @Test("Retry clears the page error without discarding loaded rows")
    func paginationRetry() {
        struct PaginationFailure: LocalizedError {
            var errorDescription: String? { "Page unavailable" }
        }

        let model = SessionTimelineModel()
        let sessionID = UUID()
        model.reset(for: sessionID)
        model.receive(page(flows: [flow(id: "one", timestamp: 1)]), for: sessionID)
        model.fail(PaginationFailure(), for: sessionID)

        model.startLoading()

        #expect(model.flows.map(\.id) == ["one"])
        #expect(model.errorMessage == nil)
        #expect(model.isLoading)
    }

    private func page(
        flows: [CaptureSessionFlow] = [],
        cursor: CaptureSessionPageCursor? = nil,
        corrupt: [String] = []
    ) -> CaptureSessionPage {
        CaptureSessionPage(flows: flows, nextCursor: cursor, corruptFlowIDs: corrupt)
    }

    private func flow(id: String, timestamp: TimeInterval) -> CaptureSessionFlow {
        let flow = FlowFixture.make(
            """
            {
              "id":"\(id)","event":"request","timestamp":\(timestamp),
              "request":{"method":"GET","url":"https://example.com/\(id)","headers":{},"body":null},
              "response":null
            }
            """
        )
        return CaptureSessionFlow(flow: flow, note: nil, isBookmarked: false)
    }
}
