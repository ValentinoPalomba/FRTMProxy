import Foundation

extension String {
    func proxySanitizedFilename() -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "item-\(UUID().uuidString)" }
        let components = trimmed.components(separatedBy: invalidCharacters)
        let collapsed = components.filter { !$0.isEmpty }.joined(separator: "_")
        return collapsed.isEmpty ? "item-\(UUID().uuidString)" : collapsed
    }
}
