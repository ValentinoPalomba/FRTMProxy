import Foundation

struct ScriptRule: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var path: String
    var code: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        path: String = "",
        code: String = ScriptRule.defaultCode,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.path = path
        self.code = code
        self.isEnabled = isEnabled
    }

    static let defaultCode = """
// flow.request: { url, method, headers, body }
// flow.response: { status, headers, body }
// Return an object to override the response, or null to pass through.
function transform(flow) {
  return null;
}
"""
}
