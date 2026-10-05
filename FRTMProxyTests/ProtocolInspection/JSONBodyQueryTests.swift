import Foundation
import Testing
@testable import FRTMProxy

@Suite("Bounded JSON body queries")
struct JSONBodyQueryTests {
    @Test func supportedPathsPreserveJSONValuesAndEscapedKeys() throws {
        let body = #"{"items":[{"id":9007199254740993,"enabled":true,"value":null},{"id":2}],"key.with.dot":{"quote\"key":"caffè"}}"#
        let wildcard = try JSONBodyQuery.evaluate(body: body, query: "$.items[*].id", mode: .path)
        #expect(wildcard.count == 2)
        #expect(wildcard.text.contains("9007199254740993"))
        let quoted = try JSONBodyQuery.evaluate(body: body, query: #"$["key.with.dot"]["quote\"key"]"#, mode: .path)
        #expect(quoted.count == 1)
        #expect(quoted.text.contains("caffè"))
        let value = try JSONBodyQuery.evaluate(body: body, query: "$.items[0].enabled", mode: .path)
        #expect(value.text.contains("true"))
        let null = try JSONBodyQuery.evaluate(body: body, query: "$.items[0].value", mode: .path)
        #expect(null.count == 1)
        #expect(null.text.contains("null"))
        #expect(try JSONBodyQuery.evaluate(body: body, query: "$.items[99].id", mode: .path).count == 0)
        #expect(try JSONBodyQuery.evaluate(body: "false", query: "$", mode: .path).text.contains("false"))
    }

    @Test func keyAndValueSearchReturnsPathsWithJSONTypes() throws {
        let body = #"{"name":"Caffè","items":[{"enabled":true,"nil":null}]}"#
        let key = try JSONBodyQuery.evaluate(body: body, query: "enabled", mode: .keyValue)
        #expect(key.count == 1)
        #expect(key.text.contains("true"))
        #expect(key.text.contains("items"))
        #expect(try JSONBodyQuery.evaluate(body: body, query: "caffe", mode: .keyValue).count == 1)
        #expect(try JSONBodyQuery.evaluate(body: body, query: "true", mode: .keyValue).count == 1)
        #expect(try JSONBodyQuery.evaluate(body: body, query: "null", mode: .keyValue).count == 1)
    }

    @Test func unsupportedSyntaxInvalidJSONAndLimitsFailExplicitly() throws {
        for path in ["items", "$..id", "$.items[-1]", "$.items[01]", "$.items[0:3]", "$.items[?(@.id)]", "$['key']", "$[\"unclosed]"] {
            #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: "{}", query: path, mode: .path) }
        }
        #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: "{truncated", query: "$", mode: .path) }
        let oversizedArray = "[" + Array(repeating: "0", count: 257).joined(separator: ",") + "]"
        #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: oversizedArray, query: "$[*]", mode: .path) }
        let tooManyNodes = "[" + Array(repeating: "0", count: 50_001).joined(separator: ",") + "]"
        #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: tooManyNodes, query: "unmatched", mode: .keyValue) }
        #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: "{}", query: "$" + String(repeating: ".key", count: 65), mode: .path) }
        let oversizedValue = "\"" + String(repeating: "a", count: 256 * 1024) + "\""
        #expect(throws: (any Error).self) { try JSONBodyQuery.evaluate(body: oversizedValue, query: "$", mode: .path) }
    }

    @Test @MainActor func latestSearchWinsAndCancelClearsBusyState() async throws {
        let model = JSONBodyQueryModel()
        model.search(body: "{\"first\":1}", query: "$.first", mode: .path)
        model.search(body: "{\"second\":2}", query: "$.second", mode: .path)
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isSearching, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.count == 1)
        #expect(model.output.contains("2"))
        #expect(!model.output.contains("1"))
        model.search(body: "{}", query: "$", mode: .path)
        model.cancel()
        #expect(!model.isSearching)
    }
}
