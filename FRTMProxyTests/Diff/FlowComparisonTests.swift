import Foundation
import Testing
@testable import FRTMProxy

@Suite("Flow comparison")
struct FlowComparisonTests {
    private func flow(_ body: String?, truncated: Bool = false, fields: [HTTPHeaderField]? = nil, reference: String? = nil) throws -> MitmFlow {
        var response: [String: Any] = ["status": 200, "headers": ["Set-Cookie": "legacy"], "bodyTruncated": truncated]
        if let body { response["body"] = body }
        if let fields { response["headerFields"] = fields.map { ["name": $0.name, "value": $0.value] } }
        if let reference { response["originalBodyReference"] = reference }
        return try JSONDecoder().decode(MitmFlow.self, from: JSONSerialization.data(withJSONObject: ["id": "test-flow", "event": "response", "response": response]))
    }
    @Test func structuralJSONPreservesTypesAndIgnoresObjectKeyOrder() throws {
        let a = try flow(#"{"big":9007199254740993,"flag":true,"empty":{},"items":[null,2]}"#)
        let b = try flow(#"{"items":[null,3],"empty":{},"flag":1,"big":9007199254740993}"#)
        let result = try FlowComparison.compare(.init(a: a, b: b, section: .responseBody, mode: .structure))
        #expect(result.rows.count == 2)
        #expect(result.rows.contains { $0.id == "$[\"flag\"]" && $0.a == "true" && $0.b == "1" })
        #expect(result.rows.contains { $0.id == "$[\"items\"][1]" && $0.a == "2" && $0.b == "3" })
        #expect(result.warning == nil)
        let equal = try flow(#"{"items":[null,2],"empty":{},"flag":true,"big":9007199254740993}"#)
        #expect(try FlowComparison.compare(.init(a: a, b: equal, section: .responseBody, mode: .structure)).rows.isEmpty)
    }
    @Test func headersPreserveOccurrencesAndMissingDiffersFromEmpty() throws {
        let a = try flow(nil, fields: [.init(name: "Set-Cookie", value: "first"), .init(name: "Set-Cookie", value: "second")])
        let b = try flow(nil, fields: [.init(name: "set-cookie", value: "first"), .init(name: "set-cookie", value: "changed"), .init(name: "X-Empty", value: "")])
        let result = try FlowComparison.compare(.init(a: a, b: b, section: .responseHeaders, mode: .structure))
        #expect(result.rows.count == 2)
        #expect(result.rows.contains { $0.id == "set-cookie[2]" && $0.a == "second" && $0.b == "changed" })
        #expect(result.rows.contains { $0.id == "x-empty[1]" && $0.a == nil && $0.b == "" })
        #expect(result.warning == nil)
        let empty = try flow("")
        let missing = try flow(nil)
        #expect(try FlowComparison.compare(.init(a: empty, b: missing, section: .responseBody, mode: .bytes)).rows.count == 1)
    }
    @Test func binaryOffsetsLimitsAndIncompleteEvidenceAreExplicit() throws {
        let a = try flow("data:application/octet-stream;base64," + Data([0, 255, 128]).base64EncodedString())
        let b = try flow("data:application/octet-stream;base64," + Data([0, 254]).base64EncodedString(), truncated: true)
        let result = try FlowComparison.compare(.init(a: a, b: b, section: .responseBody, mode: .bytes))
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.id == "byte 0")
        #expect(result.rows.first?.a == "00 ff 80")
        #expect(result.rows.first?.b == "00 fe")
        #expect(result.warning?.contains("truncated") == true)
        let missingOriginal = try flow("fallback", reference: "invalid.gcm")
        #expect(throws: (any Error).self) { try FlowComparison.compare(.init(a: missingOriginal, b: b, section: .responseBody, mode: .bytes)) }
        let huge = try flow(String(repeating: "x", count: 2 * 1024 * 1024 + 1))
        #expect(throws: (any Error).self) { try FlowComparison.compare(.init(a: huge, b: b, section: .responseBody, mode: .structure)) }
        let tooMany = try flow((0..<4001).map { "line \($0)" }.joined(separator: "\n"))
        #expect(throws: (any Error).self) { try FlowComparison.compare(.init(a: tooMany, b: try flow(""), section: .responseBody, mode: .structure)) }
    }
    @Test func textInsertionsDoNotShiftEveryFollowingLineAndCancellationIsHonored() async throws {
        let a = try flow("first\nlast"), b = try flow("first\ninserted\nlast")
        let result = try FlowComparison.compare(.init(a: a, b: b, section: .responseBody, mode: .structure))
        #expect(result.rows.count == 1)
        #expect(result.rows.first?.id == "line B 2")
        #expect(result.rows.first?.a == nil)
        #expect(result.rows.first?.b == "inserted")
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try FlowComparison.compare(.init(a: a, b: b, section: .responseBody, mode: .structure))
        }
        worker.cancel()
        do { _ = try await worker.value; Issue.record("Cancelled comparison returned a result") }
        catch { #expect(error is CancellationError) }
    }
}
