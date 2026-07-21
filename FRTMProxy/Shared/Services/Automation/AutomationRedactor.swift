import Foundation

enum AutomationRedactor {
    static func redact(
        _ message: AutomationHTTPMessage,
        using policy: RedactionPolicy = .defaults
    ) throws -> RedactedAutomationHTTPMessage {
        try policy.validate()

        let headers = redactHeaders(message.headers, using: policy)
        let url = message.url.map { redactURL($0, using: policy) }
        let bodyResult = redactBody(message.body, headers: message.headers, using: policy)

        return RedactedAutomationHTTPMessage(
            url: url,
            headers: headers,
            body: bodyResult.body,
            bodyWasOmitted: bodyResult.wasOmitted,
            bodyWasTruncated: bodyResult.wasTruncated
        )
    }

    private static func redactHeaders(
        _ headers: [String: String],
        using policy: RedactionPolicy
    ) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            let (name, value) = item
            if policy.matchesSensitiveHeader(name) {
                if policy.cookieMode == .redactNamed, name.caseInsensitiveCompare("cookie") == .orderedSame {
                    result[name] = redactCookieHeader(value, using: policy)
                } else {
                    result[name] = policy.replacement
                }
            } else {
                result[name] = value
            }
        }
    }

    private static func redactCookieHeader(_ value: String, using policy: RedactionPolicy) -> String {
        value.split(separator: ";", omittingEmptySubsequences: false).map { component in
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = pair.first else { return String(component) }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard policy.matchesSensitiveCookie(name) else { return String(component) }
            return "\(name)=\(policy.replacement)"
        }.joined(separator: ";")
    }

    private static func redactURL(_ rawURL: String, using policy: RedactionPolicy) -> String {
        guard var components = URLComponents(string: rawURL) else { return policy.replacement }
        guard let items = components.queryItems else { return rawURL }
        components.queryItems = items.map { item in
            guard policy.matchesSensitiveQueryParameter(item.name), item.value != nil else { return item }
            return URLQueryItem(name: item.name, value: policy.replacement)
        }
        return components.string ?? rawURL
    }

    private static func redactBody(
        _ body: String?,
        headers: [String: String],
        using policy: RedactionPolicy
    ) -> (body: String?, wasOmitted: Bool, wasTruncated: Bool) {
        guard let body else { return (nil, false, false) }
        guard policy.bodyMode == .includeText else { return (nil, true, false) }

        let contentType = headers.first { name, _ in
            name.caseInsensitiveCompare("content-type") == .orderedSame
        }?.value.lowercased() ?? ""

        let redacted: String
        if contentType.contains("json") {
            guard let json = redactJSON(body, using: policy) else {
                return (nil, true, false)
            }
            redacted = json
        } else if contentType.contains("application/x-www-form-urlencoded") {
            redacted = redactForm(body, using: policy)
        } else {
            redacted = body
        }

        let truncated = redacted.utf8.count > policy.maximumBodyBytes
        return (utf8Prefix(redacted, maximumBytes: policy.maximumBodyBytes), false, truncated)
    }

    private static func redactJSON(_ body: String, using policy: RedactionPolicy) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        let redacted = redactJSONObject(object, using: policy)
        guard let result = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: result, encoding: .utf8)
    }

    private static func redactJSONObject(_ value: Any, using policy: RedactionPolicy) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                let (key, child) = item
                result[key] = policy.matchesSensitiveBodyField(key)
                    ? policy.replacement
                    : redactJSONObject(child, using: policy)
            }
        }
        if let array = value as? [Any] {
            return array.map { redactJSONObject($0, using: policy) }
        }
        return value
    }

    private static func redactForm(_ body: String, using policy: RedactionPolicy) -> String {
        body.split(separator: "&", omittingEmptySubsequences: false).map { component in
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = pair.first,
                  let decodedName = String(rawName).removingPercentEncoding,
                  policy.matchesSensitiveBodyField(decodedName) else {
                return String(component)
            }
            let encodedReplacement = policy.replacement.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ?? policy.replacement
            return "\(rawName)=\(encodedReplacement)"
        }.joined(separator: "&")
    }

    private static func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var bytes = Array(value.utf8.prefix(maximumBytes))
        while !bytes.isEmpty {
            if let prefix = String(bytes: bytes, encoding: .utf8) {
                return prefix
            }
            bytes.removeLast()
        }
        return ""
    }
}
