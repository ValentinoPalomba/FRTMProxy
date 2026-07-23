import Foundation

struct MapRule: Identifiable, Hashable, Codable, Sendable {
    let key: String
    let host: String
    let path: String
    var scheme: String?
    var request: MapRuleRequest? = nil
    var body: String
    var status: Int
    var headers: [String: String]
    var isEnabled: Bool = true
    var id: String { key }

    var displayURL: String {
        let scheme = (scheme?.isEmpty ?? true) ? "https" : (scheme ?? "https")
        return "\(scheme)://\(host)\(path)"
    }
}
