import Foundation

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
