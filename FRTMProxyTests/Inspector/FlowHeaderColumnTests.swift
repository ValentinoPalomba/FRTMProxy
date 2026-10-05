import Foundation
import Testing
@testable import FRTMProxy

@Suite("Custom header columns")
struct FlowHeaderColumnTests {
    private func flow(id: String, request: [HTTPHeaderField], response: [HTTPHeaderField]) throws -> MitmFlow {
        let object: [String: Any] = ["id": id, "event": "response",
            "request": ["method": "GET", "url": "http://example.com", "headers": [:], "headerFields": request.map { ["name": $0.name, "value": $0.value] }],
            "response": ["status": 200, "headers": [:], "headerFields": response.map { ["name": $0.name, "value": $0.value] }]]
        return try JSONDecoder().decode(MitmFlow.self, from: JSONSerialization.data(withJSONObject: object))
    }
    @Test func valuesPreserveOccurrencesPhaseAndAbsenceAndSortNaturally() throws {
        let column = FlowHeaderColumn(phase: .response, name: "X-Request-ID")
        let a = try flow(id: "a", request: [.init(name: "X-Request-ID", value: "request")], response: [.init(name: "x-request-id", value: "item2"), .init(name: "X-Request-ID", value: "second")])
        let b = try flow(id: "b", request: [], response: [.init(name: "X-Request-ID", value: "item10")])
        let missing = try flow(id: "missing", request: [], response: [])
        let empty = try flow(id: "empty", request: [], response: [.init(name: "X-Request-ID", value: "")])
        #expect(column.values(in: a) == ["item2", "second"])
        #expect(FlowHeaderColumn(phase: .request, name: "x-request-id").values(in: a) == ["request"])
        #expect(column.displayValue(in: a) == "item2\nsecond")
        #expect(column.displayValue(in: missing) == nil)
        #expect(column.displayValue(in: empty) == "")
        #expect(column.sorted([b, a, missing, empty], ascending: true).map(\.id) == ["missing", "empty", "a", "b"])
        #expect(column.sorted([b, a, missing, empty], ascending: false).map(\.id) == ["b", "a", "empty", "missing"])
        let large = try flow(id: "large", request: [], response: (0..<9).map { _ in .init(name: "X-Request-ID", value: String(repeating: "é", count: 300)) })
        #expect(column.displayValue(in: large)?.contains("… (9 occurrences)") == true)
        #expect((column.displayValue(in: large)?.count ?? 0) < 2200)
    }
    @Test func configurationRoundTripsAndRejectsInvalidOrDuplicateNames() throws {
        let columns = [FlowHeaderColumn(phase: .request, name: "Authorization"), .init(phase: .response, name: "Set-Cookie")]
        #expect(try FlowHeaderColumn.decode(JSONEncoder().encode(columns)) == columns)
        #expect(try FlowHeaderColumn.decode(Data()).isEmpty)
        #expect(throws: (any Error).self) { try FlowHeaderColumn.validate(columns + [.init(phase: .response, name: "set-cookie")]) }
        #expect(throws: (any Error).self) { try FlowHeaderColumn.validate([.init(phase: .request, name: "Injected\r\nHeader")]) }
        #expect(throws: (any Error).self) { try FlowHeaderColumn.validate((0..<9).map { .init(phase: .request, name: "X-\($0)") }) }
        #expect(throws: (any Error).self) { try FlowHeaderColumn.decode(Data("invalid".utf8)) }
        #expect(throws: (any Error).self) { try FlowHeaderColumn.decode(Data(repeating: 32, count: 32769)) }
    }
}
