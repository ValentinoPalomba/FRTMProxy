import Foundation

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
