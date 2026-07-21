import Foundation

enum AutomationProtocol {
    static let currentSchemaVersion = 1
    static let currentProtocolVersion = "1.0"
}

struct AutomationRequest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var protocolVersion: String
    let id: UUID
    let method: String
    var parameters: [String: AutomationJSONValue]

    init(
        schemaVersion: Int = AutomationProtocol.currentSchemaVersion,
        protocolVersion: String = AutomationProtocol.currentProtocolVersion,
        id: UUID = UUID(),
        method: String,
        parameters: [String: AutomationJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.protocolVersion = protocolVersion
        self.id = id
        self.method = method
        self.parameters = parameters
    }
}

struct AutomationResponse: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var protocolVersion: String
    let id: UUID
    var result: AutomationJSONValue?
    var error: AutomationResponseError?

    init(
        schemaVersion: Int = AutomationProtocol.currentSchemaVersion,
        protocolVersion: String = AutomationProtocol.currentProtocolVersion,
        id: UUID,
        result: AutomationJSONValue? = nil,
        error: AutomationResponseError? = nil
    ) {
        precondition(result == nil || error == nil, "A response cannot contain both a result and an error.")
        self.schemaVersion = schemaVersion
        self.protocolVersion = protocolVersion
        self.id = id
        self.result = result
        self.error = error
    }
}

struct AutomationResponseError: Codable, Equatable, Sendable {
    let code: String
    let message: String
    var details: [String: AutomationJSONValue]

    init(code: String, message: String, details: [String: AutomationJSONValue] = [:]) {
        self.code = code
        self.message = message
        self.details = details
    }
}
