import Foundation
import Testing
@testable import FRTMProxy

@Suite("Automation contracts")
struct AutomationContractsTests {
    @Test("MCP initialize contract remains compatible")
    @MainActor
    func mcpInitializeContract() async throws {
        let router = MCPAutomationRouter(
            flowProvider: { [] },
            ruleUpdater: { _ in }
        )
        let request = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.utf8)
        let responseData = try #require(await router.handle(request))
        let response = try #require(
            try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let result = try #require(response["result"] as? [String: Any])
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])

        #expect(response["jsonrpc"] as? String == "2.0")
        #expect(response["id"] as? Int == 1)
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect(serverInfo["name"] as? String == "FRTMProxy")
        #expect(serverInfo["version"] as? String == "1.0")
    }

    @Test("replace_rules acknowledges only a successful commit")
    @MainActor
    func replaceRulesReportsCommitFailure() async throws {
        struct CommitFailure: LocalizedError {
            var errorDescription: String? { "Persistence failed" }
        }

        let router = MCPAutomationRouter(
            flowProvider: { [] },
            ruleUpdater: { _ in throw CommitFailure() }
        )
        let request = Data(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_rules","arguments":{"document":{"schemaVersion":1,"rules":[]}}}}"#.utf8
        )
        let responseData = try #require(await router.handle(request))
        let response = try #require(
            try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])

        #expect(result["isError"] as? Bool == true)
        #expect(content.first?["text"] as? String == "Persistence failed")
    }

    @Test("Request and response DTOs survive Codable round trips")
    func codableRoundTrips() throws {
        let request = AutomationRequest(
            id: UUID(uuidString: "9C091EF5-96DB-4C2A-96DA-D29DC5449E79") ?? UUID(),
            method: "flows.list",
            parameters: [
                "limit": .number(25),
                "filters": .array([.string("host:example.com")]),
                "options": .object(["includeBodies": .bool(false)]),
                "cursor": .null
            ]
        )
        let requestData = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(AutomationRequest.self, from: requestData) == request)

        let response = AutomationResponse(id: request.id, result: .object(["count": .number(4)]))
        let responseData = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(AutomationResponse.self, from: responseData) == response)
    }

    @Test("Limit configuration rejects invalid and oversized inputs")
    func limitValidation() throws {
        let limits = AutomationLimits(
            maximumRequestBytes: 10,
            maximumResponseBytes: 20,
            maximumBodyBytes: 5,
            maximumBatchItems: 2,
            requestsPerMinute: 1
        )
        try limits.validate()
        try limits.validateRequest(byteCount: 10)
        try limits.validateResponse(byteCount: 20)
        try limits.validateBatch(itemCount: 2)

        #expect(throws: AutomationLimitError.self) {
            try limits.validateRequest(byteCount: 11)
        }
        #expect(throws: AutomationLimitError.self) {
            try limits.validateResponse(byteCount: 21)
        }
        #expect(throws: AutomationLimitError.self) {
            try limits.validateBatch(itemCount: 3)
        }
        #expect(throws: AutomationLimitError.self) {
            try AutomationLimits(maximumRequestBytes: 1, maximumResponseBytes: 2, maximumBodyBytes: 3).validate()
        }
    }
}
