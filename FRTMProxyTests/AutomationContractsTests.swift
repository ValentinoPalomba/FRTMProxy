import Foundation
import Testing
@testable import FRTMProxy

@Suite("Automation contracts")
struct AutomationContractsTests {
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
