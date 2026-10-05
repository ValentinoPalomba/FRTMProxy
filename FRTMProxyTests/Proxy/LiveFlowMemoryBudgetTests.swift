import Foundation
import Testing
@testable import FRTMProxy

@Suite("Live flow memory budget")
struct LiveFlowMemoryBudgetTests {
    @Test func byteBudgetRetainsRecentAndPausedFlowsWithStableTies() throws {
        func flow(_ id: String, _ timestamp: Double, paused: Bool = false) -> MitmFlow {
            var result = MitmFlow(id: id, event: "response")
            result.timestamp = timestamp
            if paused { result.breakpoint = .init(phase: .response, state: .waiting, key: id) }
            return result
        }
        let flows = [flow("paused", 0, paused: true), flow("old", 1), flow("new", 2), flow("huge", 3)]
        let map = Dictionary(uniqueKeysWithValues: flows.map { ($0.id, $0) })
        let weights = ["paused": 10, "old": 10, "new": 10, "huge": 100]
        let retained = LiveFlowMemoryBudget.retain(map, weights: weights, maximumCount: 3, maximumBytes: 20)
        #expect(Set(retained.keys) == ["paused", "new"])
        let ties = ["b": flow("b", 1), "a": flow("a", 1)]
        #expect(Set(LiveFlowMemoryBudget.retain(ties, weights: ["a": 10, "b": 10], maximumCount: 1, maximumBytes: 20).keys) == ["a"])
        #expect(LiveFlowMemoryBudget.retain(map, weights: weights, maximumCount: 0, maximumBytes: 20).isEmpty)
    }
    @Test func webSocketBudgetKeepsRecentFramesAndMarksOversizedOmissions() throws {
        var flow = MitmFlow(id: "ws", event: "websocket_message")
        let frames = (0..<4).map { WebSocketMessage(id: "\($0)", direction: .server, type: .text, content: "1234", timestamp: Double($0)) }
        flow.websocketMessages = frames
        let full = flow
        #expect(LiveFlowMemoryBudget.trimWebSocket(&flow, maximumBytes: 8) == 2)
        #expect(flow.websocketMessages.map(\.id) == ["2", "3"])
        #expect(full.websocketMessages.count == 4)
        #expect(flow.livePreviewWarning != nil)
        #expect(LiveFlowMemoryBudget.trimWebSocket(&flow, maximumBytes: 2) == 2)
        #expect(flow.websocketMessages.isEmpty)
        flow.websocketMessages = (0..<1001).map { .init(id: "\($0)", direction: .client, type: .text, content: "", timestamp: Double($0)) }
        #expect(LiveFlowMemoryBudget.trimWebSocket(&flow) == 1)
        #expect(flow.websocketMessages.first?.id == "1")
        let encoded = try JSONEncoder().encode(flow)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("livePreviewWarning"))
    }
    @Test func payloadCostIncludesRepeatedHeadersAndBinaryPreviewAndFrames() {
        var flow = MitmFlow(id: "flow", event: "response")
        flow.request = .init(method: "POST", url: "http://example.com", headers: ["X": "é"], body: "data:application/octet-stream;base64,AAAA", headerFields: [.init(name: "X", value: "é"), .init(name: "X", value: "二")])
        let before = LiveFlowMemoryBudget.cost(flow)
        flow.websocketMessages = [.init(id: "ws", direction: .client, type: .binary, content: "data:application/octet-stream;base64,AQID", timestamp: 1)]
        #expect(LiveFlowMemoryBudget.cost(flow) > before)
        var big = MitmFlow(id: "big", event: "response")
        big.response = .init(status: 200, headers: nil, body: String(repeating: "x", count: 2 * 1024 * 1024))
        #expect(LiveFlowMemoryBudget.cost(big) > 2 * 1024 * 1024)
    }
}
