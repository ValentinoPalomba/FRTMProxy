import Foundation

enum ComposerTemplate {
    struct Request: Sendable {
        let url: URL
        let transportURL: String
        let method: String
        let headers: [HTTPHeaderField]
        let body: Data?
    }
    static let httpMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    enum Failure: LocalizedError {
        case variable(String), invalidRequest
        var errorDescription: String? {
            switch self {
            case let .variable(name): "Undefined, duplicate or invalid variable: \(name)"
            case .invalidRequest: "Use an HTTP(S) URL and valid headers without line breaks. Maximum body: 2 MiB."
            }
        }
    }
    static func request(_ draft: ComposerDraft, variables: [ComposerHeaderRow]) throws -> Request {
        guard draft.headers.count <= 128, variables.count <= 128 else { throw Failure.invalidRequest }
        var values: [String: String] = [:]
        let pattern = try NSRegularExpression(pattern: #"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}"#)
        let namePattern = try NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#)
        for row in variables {
            let name = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty && row.value.isEmpty { continue }
            guard namePattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil,
                  values[name] == nil else { throw Failure.variable(name) }
            values[name] = row.value
        }
        func expand(_ source: String) throws -> String {
            let unmatched = pattern.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "")
            guard !unmatched.contains("{{") else { throw Failure.variable("Use {{NAME}} syntax") }
            var output = source
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
                guard let nameRange = Range(match.range(at: 1), in: source),
                      let range = Range(match.range, in: output) else { throw Failure.invalidRequest }
                let name = String(source[nameRange])
                guard let value = values[name] else { throw Failure.variable(name) }
                output.replaceSubrange(range, with: value)
                guard output.utf8.count <= 2 * 1024 * 1024 else { throw Failure.invalidRequest }
            }
            return output
        }
        let rawURL = try expand(draft.url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              httpMethods.contains(draft.method) else { throw Failure.invalidRequest }
        guard rawURL.utf8.count <= 8192 else { throw Failure.invalidRequest }
        var headerBytes = 0
        var fields: [HTTPHeaderField] = []
        for row in draft.headers {
            let name = try expand(row.key).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = try expand(row.value)
            if name.isEmpty { continue }
            headerBytes += name.utf8.count + value.utf8.count
            guard headerBytes <= 64 * 1024 else { throw Failure.invalidRequest }
            guard HTTPHeaderField.isValidName(name),
                  !value.utf8.contains(13), !value.utf8.contains(10), !value.utf8.contains(0) else { throw Failure.invalidRequest }
            // Recompute transport framing from the bytes actually sent.
            if !["content-length", "transfer-encoding"].contains(name.lowercased()) {
                fields.append(.init(name: name, value: value))
            }
        }
        let body = try expand(draft.body)
        guard body.utf8.count <= (draft.bodyIsBase64 == true ? 4 * ((2 * 1024 * 1024 + 2) / 3) : 2 * 1024 * 1024) else { throw Failure.invalidRequest }
        let bytes: Data?
        if draft.bodyIsBase64 == true {
            guard let decoded = Data(base64Encoded: body), decoded.count <= 2 * 1024 * 1024 else { throw Failure.invalidRequest }
            bytes = decoded
        } else {
            bytes = body.isEmpty ? nil : Data(body.utf8)
        }
        return Request(url: url, transportURL: rawURL, method: draft.method, headers: fields, body: bytes)
    }
}
