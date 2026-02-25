import Foundation

extension MitmFlow {
    var formattedStartTimestamp: String {
        guard let start = requestTimestamp ?? timestamp else { return "—" }
        let date = Date(timeIntervalSince1970: start)
        return DateFormatter.cachedTime.string(from: date)
    }

    var formattedEndTimestamp: String {
        guard let end = responseTimestamp else { return "—" }
        let date = Date(timeIntervalSince1970: end)
        return DateFormatter.cachedTime.string(from: date)
    }

    var formattedTimestamp: String {
        formattedStartTimestamp
    }

    var duration: TimeInterval? {
        guard let start = requestTimestamp ?? timestamp,
              let end = responseTimestamp else {
            return nil
        }
        let elapsed = end - start
        guard elapsed >= 0 else { return nil }
        return elapsed
    }

    var formattedDuration: String {
        guard let duration else { return "—" }
        if duration < 1 {
            let milliseconds = (duration * 1000).rounded()
            return "\(Int(milliseconds)) ms"
        }
        if duration < 10 {
            return duration.formatted(.number.precision(.fractionLength(2))) + " s"
        }
        return duration.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    var clientIP: String {
        (client?.ip ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var xRequestID: String? {
        guard let headers = request?.headers else { return nil }
        for (key, value) in headers {
            if key.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("x-request-id") == .orderedSame {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }
    
    var isMapped: Bool {
        (response?.headers?["X-Map-Local"] ?? response?.headers?["x-map-local"]) != nil
    }

    var host: String {
        guard let urlString = request?.url,
              let url = URL(string: urlString) else {
            return ""
        }
        return url.host ?? urlString
    }
    
    var path: String {
        guard let urlString = request?.url,
              let url = URL(string: urlString) else {
            return ""
        }
        return url.path
    }

    var sharePreviewTitle: String {
        let method = request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let path = self.path.isEmpty ? "/" : self.path
        if method.isEmpty {
            return "\(host)\(path)"
        }
        return "\(method) \(host)\(path)"
    }

    var teamsShareText: String? {
        guard let request else { return nil }

        var lines: [String] = []
        lines.append("FRTMProxy – Flow")

        if !formattedTimestamp.isEmpty {
            lines.append("Time: \(formattedTimestamp)")
        }

        let client = clientIP
        let appName = clientApp?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !client.isEmpty && !appName.isEmpty {
            lines.append("Client: \(client) (\(appName))")
        } else if !client.isEmpty {
            lines.append("Client: \(client)")
        } else if !appName.isEmpty {
            lines.append("Client: \(appName)")
        }

        lines.append("")
        lines.append("Request: \(request.method.uppercased()) \(request.url)")

        if let requestID = xRequestID {
            lines.append("X-Request-ID: \(requestID)")
        }

        if let status = response?.status {
            lines.append("Status: \(status)")
        }

        if let curl = curlString, !curl.isEmpty {
            lines.append("")
            lines.append("cURL:")
            lines.append("```bash")
            lines.append(curl)
            lines.append("```")
        }

        if !request.headers.isEmpty {
            lines.append("")
            lines.append("Request headers:")
            lines.append(contentsOf: Self.formattedHeaders(request.headers))
        }

        if let body = request.body, !body.isEmpty {
            lines.append("")
            lines.append("Request body:")
            lines.append("```")
            lines.append(Self.truncated(body))
            lines.append("```")
        }

        if let response {
            let responseHeaders = response.headers ?? [:]
            if !responseHeaders.isEmpty {
                lines.append("")
                lines.append("Response headers:")
                lines.append(contentsOf: Self.formattedHeaders(responseHeaders))
            }

            if let responseBody = response.body, !responseBody.isEmpty {
                lines.append("")
                lines.append("Response body:")
                lines.append("```")
                lines.append(Self.truncated(responseBody))
                lines.append("```")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formattedHeaders(_ headers: [String: String]) -> [String] {
        headers
            .sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
            .prefix(40)
            .map { "- \($0.key): \($0.value)" }
    }

    private static func truncated(_ value: String, limit: Int = 4000) -> String {
        if value.count <= limit {
            return value
        }
        let prefix = value.prefix(limit)
        return prefix + "\n…(truncated)"
    }
    
    var curlString: String? {
        guard let req = request else { return nil }
        var components: [String] = ["curl", "-X", req.method]
        components.append("\"\(req.url)\"")
        
        for (key, value) in req.headers {
            components.append("-H")
            components.append("\"\(key): \(value)\"")
        }
        
        if let body = req.body, !body.isEmpty {
            let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("--data-binary")
            components.append("\"\(escaped)\"")
        }
        
        return components.joined(separator: " ")
    }
    
    var breakpointPhase: FlowBreakpointPhase? {
        breakpoint?.phase
    }
    
    var isBreakpointWaiting: Bool {
        breakpoint?.state == .waiting
    }
    
    var breakpointKey: String? {
        breakpoint?.key
    }
}
