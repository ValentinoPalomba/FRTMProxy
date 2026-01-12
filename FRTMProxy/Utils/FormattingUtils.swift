import Foundation

enum FormattingUtils {
    static func formattedBodyForEdit(_ body: String?) -> String {
        guard let body, let data = body.data(using: .utf8) else { return body ?? "" }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return body
    }

    static func formattedHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0): \($1)" }
            .joined(separator: "\n")
    }

    static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        text.split(separator: "\n").forEach { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty {
                result[parts[0]] = parts[1]
            }
        }
        return result
    }
}

