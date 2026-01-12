import Foundation

struct FlowFilter: Equatable {
    var searchText: String = ""
    var showMappedOnly: Bool = false
    var showErrorsOnly: Bool = false
    var activePinnedHosts: Set<String> = []
    var activeClientIPs: Set<String> = []

    func apply(to flows: [MitmFlow]) -> [MitmFlow] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !showMappedOnly, !showErrorsOnly, activePinnedHosts.isEmpty, activeClientIPs.isEmpty, trimmedSearch.isEmpty {
            return flows
        }

        let query = FlowQuery.parse(searchText)
        let pinnedHosts = activePinnedHosts
        let activeClients = activeClientIPs
        return flows.filter { flow in
            if showMappedOnly && !flow.isMapped { return false }
            if showErrorsOnly, let status = flow.response?.status, status < 400 { return false }
            if !pinnedHosts.isEmpty {
                let host = PinnedHost.normalized(flow.host)
                if host.isEmpty || !pinnedHosts.contains(host) {
                    return false
                }
            }
            if !activeClients.isEmpty {
                let clientIP = flow.clientIP
                if clientIP.isEmpty || !activeClients.contains(clientIP) {
                    return false
                }
            }
            if query.isEmpty { return true }
            return query.matches(flow)
        }
    }

    mutating func updateActivePinnedHosts(_ hosts: [String]) {
        activePinnedHosts = Set(hosts.map { PinnedHost.normalized($0) }.filter { !$0.isEmpty })
    }

    mutating func toggleClientIP(_ ip: String) {
        let normalized = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if activeClientIPs.contains(normalized) {
            activeClientIPs.remove(normalized)
        } else {
            activeClientIPs.insert(normalized)
        }
    }
}

private struct FlowQuery {
    var keywords: [String] = []
    var excludedKeywords: [String] = []
    var hostTerms: [String] = []
    var pathTerms: [String] = []
    var urlTerms: [String] = []
    var clientTerms: [String] = []
    var excludedClientTerms: [String] = []
    var methods: Set<String> = []
    var excludedMethods: Set<String> = []
    var statusPredicate: ((Int) -> Bool)?
    var contentTypeTerms: [String] = []
    var excludedContentTypeTerms: [String] = []

    var isEmpty: Bool {
        keywords.isEmpty &&
            excludedKeywords.isEmpty &&
            hostTerms.isEmpty &&
            pathTerms.isEmpty &&
            urlTerms.isEmpty &&
            clientTerms.isEmpty &&
            excludedClientTerms.isEmpty &&
            methods.isEmpty &&
            excludedMethods.isEmpty &&
            statusPredicate == nil &&
            contentTypeTerms.isEmpty &&
            excludedContentTypeTerms.isEmpty
    }

    func matches(_ flow: MitmFlow) -> Bool {
        if isEmpty { return true }

        let request = flow.request
        let response = flow.response

        let urlString = request?.url ?? ""
        let url = URLComponents(string: urlString)

        let host = PinnedHost.normalized(url?.host ?? urlString)
        let path = (url?.path ?? "").lowercased()
        let urlLowercased = urlString.lowercased()
        let method = (request?.method ?? "").uppercased()
        let status = response?.status
        let clientIP = flow.clientIP.lowercased()

        if !methods.isEmpty && !methods.contains(method) { return false }
        if excludedMethods.contains(method) { return false }

        if let predicate = statusPredicate {
            guard let status else { return false }
            if !predicate(status) { return false }
        }

        for term in hostTerms where !term.isEmpty {
            if !host.localizedStandardContains(term) { return false }
        }
        for term in pathTerms where !term.isEmpty {
            if !path.localizedStandardContains(term) { return false }
        }
        for term in urlTerms where !term.isEmpty {
            if !urlLowercased.localizedStandardContains(term) { return false }
        }
        for term in clientTerms where !term.isEmpty {
            if !clientIP.localizedStandardContains(term) { return false }
        }
        for term in excludedClientTerms where !term.isEmpty {
            if clientIP.localizedStandardContains(term) { return false }
        }

        let contentType = Self.headerValue("content-type", in: response?.headers)?.lowercased() ?? ""
        for term in contentTypeTerms where !term.isEmpty {
            if !Self.matchesContentType(term: term, headerValue: contentType, responseBody: response?.body) { return false }
        }
        for term in excludedContentTypeTerms where !term.isEmpty {
            if Self.matchesContentType(term: term, headerValue: contentType, responseBody: response?.body) { return false }
        }

        if !keywords.isEmpty || !excludedKeywords.isEmpty {
            let requestHeaders = Self.allHeadersLowercased(request?.headers)
            let responseHeaders = Self.allHeadersLowercased(response?.headers)
            let haystack = [
                urlLowercased,
                method.lowercased(),
                host,
                path,
                requestHeaders,
                responseHeaders,
                request?.body?.lowercased() ?? "",
                response?.body?.lowercased() ?? ""
            ].joined(separator: " ")

            for keyword in keywords where !keyword.isEmpty {
                if !haystack.localizedStandardContains(keyword) { return false }
            }
            for keyword in excludedKeywords where !keyword.isEmpty {
                if haystack.localizedStandardContains(keyword) { return false }
            }
        }
        return true
    }

    static func parse(_ raw: String) -> FlowQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return FlowQuery() }

        var query = FlowQuery()
        for token in tokenize(trimmed) {
            guard !token.isEmpty else { continue }

            let (isExcluded, bare) = token.hasPrefix("-")
                ? (true, String(token.dropFirst()))
                : (false, token)

            if bare.contains(":"), let (key, value) = splitOnce(bare, separator: ":") {
                query.applyKey(key: key, value: value, excluded: isExcluded)
            } else {
                if isExcluded {
                    query.excludedKeywords.append(bare.lowercased())
                } else {
                    query.keywords.append(bare.lowercased())
                }
            }
        }

        if query.keywords.isEmpty, query.excludedKeywords.isEmpty,
           query.hostTerms.isEmpty, query.pathTerms.isEmpty, query.urlTerms.isEmpty,
           query.clientTerms.isEmpty, query.excludedClientTerms.isEmpty,
           query.methods.isEmpty, query.excludedMethods.isEmpty,
           query.statusPredicate == nil,
           query.contentTypeTerms.isEmpty, query.excludedContentTypeTerms.isEmpty {
            return FlowQuery()
        }

        query.keywords = query.keywords.filter { !$0.isEmpty }
        query.excludedKeywords = query.excludedKeywords.filter { !$0.isEmpty }
        query.clientTerms = query.clientTerms.filter { !$0.isEmpty }
        query.excludedClientTerms = query.excludedClientTerms.filter { !$0.isEmpty }
        return query
    }

    private mutating func applyKey(key: String, value: String, excluded: Bool) {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else { return }

        switch normalizedKey {
        case "host", "domain":
            let term = PinnedHost.normalized(normalizedValue)
            if !term.isEmpty { hostTerms.append(term) }
        case "device", "client", "ip":
            let term = normalizedValue.lowercased()
            if excluded {
                excludedClientTerms.append(term)
            } else {
                clientTerms.append(term)
            }
        case "path":
            pathTerms.append(normalizedValue.lowercased())
        case "url":
            urlTerms.append(normalizedValue.lowercased())
        case "method":
            let method = normalizedValue.uppercased()
            if excluded {
                excludedMethods.insert(method)
            } else {
                methods.insert(method)
            }
        case "status", "code":
            if let predicate = Self.parseStatusPredicate(normalizedValue.lowercased()) {
                statusPredicate = predicate
            }
        case "type", "content-type", "mime":
            let term = normalizedValue.lowercased()
            if excluded {
                excludedContentTypeTerms.append(term)
            } else {
                contentTypeTerms.append(term)
            }
        default:
            if excluded {
                excludedKeywords.append((key + ":" + value).lowercased())
            } else {
                keywords.append((key + ":" + value).lowercased())
            }
        }
    }

    private static func parseStatusPredicate(_ raw: String) -> ((Int) -> Bool)? {
        let value = raw.replacingOccurrences(of: " ", with: "")

        if value.count == 3, value.hasSuffix("xx"), let hundred = Int(value.prefix(1)) {
            let min = hundred * 100
            let max = min + 99
            return { $0 >= min && $0 <= max }
        }

        if value.contains("-"), let (lhs, rhs) = splitOnce(value, separator: "-"),
           let min = Int(lhs), let max = Int(rhs) {
            return { $0 >= min && $0 <= max }
        }

        for op in [">=", "<=", ">", "<"] {
            if value.hasPrefix(op), let number = Int(value.dropFirst(op.count)) {
                switch op {
                case ">=": return { $0 >= number }
                case "<=": return { $0 <= number }
                case ">": return { $0 > number }
                case "<": return { $0 < number }
                default: break
                }
            }
        }

        if let number = Int(value) {
            return { $0 == number }
        }
        return nil
    }

    private static func matchesContentType(term: String, headerValue: String, responseBody: String?) -> Bool {
        if !headerValue.isEmpty, headerValue.contains(term) { return true }
        guard term == "json" else { return false }
        let body = (responseBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.hasPrefix("{") || body.hasPrefix("[")
    }

    private static func headerValue(_ name: String, in headers: [String: String]?) -> String? {
        guard let headers else { return nil }
        let lower = name.lowercased()
        if let direct = headers[name] { return direct }
        return headers.first(where: { $0.key.lowercased() == lower })?.value
    }

    private static func allHeadersLowercased(_ headers: [String: String]?) -> String {
        guard let headers else { return "" }
        return headers
            .map { "\($0.key.lowercased()):\($0.value.lowercased())" }
            .joined(separator: " ")
    }

    private static func splitOnce(_ string: String, separator: Character) -> (String, String)? {
        guard let idx = string.firstIndex(of: separator) else { return nil }
        let lhs = String(string[..<idx])
        let rhs = String(string[string.index(after: idx)...])
        return (lhs, rhs)
    }

    private static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for char in string {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
