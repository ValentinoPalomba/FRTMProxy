import CryptoKit
import Foundation

enum MapRuleKeyBuilder {
    static func baseKey(host: String, path: String) -> String {
        let normalizedPath = path.isEmpty ? "/" : path
        return host + normalizedPath
    }

    static func makeKey(
        host: String,
        path: String,
        method: String?,
        url: String?,
        headers: [String: String],
        body: String?
    ) -> String {
        let base = baseKey(host: host, path: path)
        let signature = canonicalSignature(
            method: method,
            url: url,
            headers: headers,
            body: body
        )
        let digest = SHA256.hash(data: Data(signature.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        let prefix = String(hex.prefix(12))
        return base + "#" + prefix
    }

    static func disambiguatedKey(preferredKey: String, existingKeys: Set<String>) -> String {
        guard existingKeys.contains(preferredKey) else { return preferredKey }
        var counter = 2
        while true {
            let candidate = preferredKey + "~" + String(counter)
            if !existingKeys.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    static func baseKey(from key: String) -> String {
        if let index = key.firstIndex(of: "#") {
            return String(key[..<index])
        }
        return key
    }

    static func variantTag(from key: String) -> String? {
        guard let index = key.firstIndex(of: "#") else { return nil }
        let suffix = key[key.index(after: index)...]
        return suffix.isEmpty ? nil : String(suffix)
    }

    private static func canonicalSignature(
        method: String?,
        url: String?,
        headers: [String: String],
        body: String?
    ) -> String {
        let normalizedMethod = (method?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "GET"
        let queryCanonical = canonicalQuery(fromURL: url)
        let bodyCanonical = canonicalBody(body, contentType: contentType(from: headers))
        return normalizedMethod + "\n" + queryCanonical + "\n" + bodyCanonical
    }

    private static func canonicalQuery(fromURL urlString: String?) -> String {
        // Deve combaciare con `canonical_query` di bridge.py, che usa
        // `parse_qsl(keep_blank_values=True)`: `+`→spazio *prima* del percent-decoding.
        // Si usa `percentEncodedQuery` (query grezza) e la stessa logica del body
        // form-urlencoded, altrimenti `URLComponents.queryItems` decodificherebbe
        // `%2B` in `+` e lo convertirebbe erroneamente in spazio.
        guard let urlString,
              let rawQuery = URLComponents(string: urlString)?.percentEncodedQuery,
              !rawQuery.isEmpty else { return "" }
        return canonicalURLEncoded(rawQuery)
    }

    private static func contentType(from headers: [String: String]) -> String {
        for (key, value) in headers {
            if key.lowercased() == "content-type" {
                return value
            }
        }
        return ""
    }

    private static func canonicalBody(_ body: String?, contentType: String) -> String {
        guard var body = body else { return "" }
        body = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lower = contentType.lowercased()

        if lower.contains("application/json") {
            if let normalized = normalizedJSONString(body) {
                return normalized
            }
        }

        if lower.contains("application/x-www-form-urlencoded") {
            return canonicalURLEncoded(body)
        }

        return body
    }

    private static func normalizedJSONString(_ body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let normalizedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: normalizedData, encoding: .utf8)
    }

    /// Canonicalizza una stringa `application/x-www-form-urlencoded` (query o body)
    /// replicando `parse_qsl(keep_blank_values=True)` di Python: coppie ordinate,
    /// `+`→spazio prima del percent-decoding. Usata sia per la query dell'URL sia per
    /// il body form-urlencoded, così i due lati restano identici a bridge.py.
    private static func canonicalURLEncoded(_ raw: String) -> String {
        let pairs = raw.split(separator: "&").map(String.init).compactMap { part -> (String, String)? in
            if part.isEmpty { return nil }
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let rawName = pieces.first ?? ""
            let rawValue = pieces.count > 1 ? pieces[1] : ""
            let name = rawName.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawName
            let value = rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawValue
            return (name, value)
        }

        let sorted = pairs.sorted { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        if sorted.isEmpty { return "" }
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }
}
