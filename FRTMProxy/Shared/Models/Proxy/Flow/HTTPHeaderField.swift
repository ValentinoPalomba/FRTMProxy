import Foundation

struct HTTPHeaderField: Codable, Equatable, Sendable {
    static func isValidName(_ name: String) -> Bool {
        let token = "!#$%&'*+-.^_`|~"
        return !name.isEmpty && name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || token.utf8.contains($0)
        }
    }
    let name: String
    let value: String
}
