import Foundation

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
