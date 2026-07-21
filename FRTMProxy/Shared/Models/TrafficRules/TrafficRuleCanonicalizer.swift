import Foundation

/// Canonicalization contract for request matching.
///
/// Query strings and form bodies follow Python's `parse_qsl(keep_blank_values=True)`:
/// `+` becomes a space before percent-decoding and pairs sort by name then value.
/// JSON object keys are sorted, while invalid JSON and all other bodies remain unchanged
/// after CRLF/CR line endings are normalized to LF.
enum TrafficRuleCanonicalizer {
    static func method(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return normalized.isEmpty ? "GET" : normalized
    }

    static func query(from url: String?) -> String {
        guard let url,
              let query = URLComponents(string: url)?.percentEncodedQuery,
              !query.isEmpty else { return "" }
        return urlEncoded(query)
    }

    static func body(_ value: String?, contentType: String?) -> String {
        guard var value else { return "" }
        value = value.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        let contentType = contentType?.lowercased() ?? ""

        if contentType.contains("application/json"),
           let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let canonicalData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let canonical = String(data: canonicalData, encoding: .utf8) {
            return canonical
        }
        if contentType.contains("application/x-www-form-urlencoded") {
            return urlEncoded(value)
        }
        return value
    }

    private static func urlEncoded(_ value: String) -> String {
        let pairs = value.split(separator: "&").compactMap { part -> (String, String)? in
            guard !part.isEmpty else { return nil }
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawName = String(pieces.first ?? "")
            let rawValue = pieces.count > 1 ? String(pieces[1]) : ""
            return (decodeFormComponent(rawName), decodeFormComponent(rawValue))
        }
        return pairs.sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private static func decodeFormComponent(_ value: String) -> String {
        let plusDecoded = value.replacing("+", with: " ")
        return plusDecoded.removingPercentEncoding ?? value
    }
}
