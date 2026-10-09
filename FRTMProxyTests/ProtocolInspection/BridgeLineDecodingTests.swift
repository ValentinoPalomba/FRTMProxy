import Foundation
import Testing
@testable import FRTMProxy

@Suite("Bridge line routing")
struct BridgeLineDecodingTests {
    @Test func flowPayloadPreservesUnicodeAndCompleteBody() throws {
        let body = String(repeating: "è漢字\\n", count: 4096)
        let object: [String: Any] = ["id": "flow", "event": "response", "request": ["method": "GET", "url": "https://example.test/", "headers": [:]], "response": ["status": 200, "headers": [:], "body": body]]
        let data = try JSONSerialization.data(withJSONObject: object)
        guard case let .flow(flow) = MitmproxyService.decodeBridgeLine(data) else { Issue.record("Response routed incorrectly"); return }
        #expect(flow.response?.body == body)
        #expect(flow.id == "flow")
    }

    @Test func controlsAndMalformedLinesNeverBecomeFlows() {
        guard case let .ready(id) = MitmproxyService.decodeBridgeLine(Data(#"{"event":"proxy_ready","startup_id":"launch"}"#.utf8)) else { Issue.record("Ready routed incorrectly"); return }
        #expect(id == "launch")
        guard case let .rules(event) = MitmproxyService.decodeBridgeLine(Data(#"{"event":"rules_error","revision":3,"message":"invalid"}"#.utf8)) else { Issue.record("Rules routed incorrectly"); return }
        #expect(event.revision == 3)
        #expect(event.event == .failed)
        guard case let .captureMessage(message) = MitmproxyService.decodeBridgeLine(Data(#"{"event":"capture_warning","message":"incomplete"}"#.utf8)) else { Issue.record("Warning routed incorrectly"); return }
        #expect(message == "incomplete")
        for line in ["not JSON", #"{"event":"rules_ack"}"#, #"{"event":"websocket_message","id":"partial"}"#] {
            guard case .unknown = MitmproxyService.decodeBridgeLine(Data(line.utf8)) else { Issue.record("Malformed control frame accepted"); continue }
        }
    }
}
