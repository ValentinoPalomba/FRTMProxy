import Foundation

struct FlowFilter: Equatable, Sendable {
    var searchText: String = ""
    var showMappedOnly: Bool = false
    var showErrorsOnly: Bool = false
    var activePinnedHosts: Set<String> = []
    var activePinnedApps: Set<String> = []
    var activeClientIPs: Set<String> = []

    func apply(to flows: [MitmFlow]) -> [MitmFlow] {
        apply(to: flows, using: Cache())
    }

    func apply(to flows: [MitmFlow], using cache: Cache) -> [MitmFlow] {
        (try? applyCancellable(to: flows, using: cache)) ?? []
    }

    func applyCancellable(to flows: [MitmFlow], using cache: Cache) throws -> [MitmFlow] {
        try Task.checkCancellation()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !showMappedOnly, !showErrorsOnly, activePinnedHosts.isEmpty, activePinnedApps.isEmpty, activeClientIPs.isEmpty, trimmedSearch.isEmpty {
            cache.retain(flowIDs: Set(flows.map(\.id)))
            return flows
        }

        let query = FlowQuery.parse(searchText)
        let pinnedHosts = activePinnedHosts
        let pinnedApps = activePinnedApps
        let activeClients = activeClientIPs
        var filtered: [MitmFlow] = []
        filtered.reserveCapacity(flows.count)

        for (index, flow) in flows.enumerated() {
            if index.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
            if showMappedOnly && !flow.isMapped { continue }
            if showErrorsOnly, let status = flow.response?.status, status < 400 { continue }
            var projection: FlowProjection?
            if !pinnedHosts.isEmpty {
                let cachedProjection = cache.projection(for: flow)
                projection = cachedProjection
                let host = cachedProjection.host
                if host.isEmpty || !pinnedHosts.contains(host) {
                    continue
                }
            }
            if !pinnedApps.isEmpty {
                let appID = flow.clientApp?.id ?? ""
                if appID.isEmpty || !pinnedApps.contains(appID) {
                    continue
                }
            }
            if !activeClients.isEmpty {
                let clientIP = flow.clientIP
                if clientIP.isEmpty || !activeClients.contains(clientIP) {
                    continue
                }
            }
            if query.isEmpty || query.matches(projection ?? cache.projection(for: flow)) {
                filtered.append(flow)
            }
        }

        try Task.checkCancellation()
        cache.retain(flowIDs: Set(flows.map(\.id)))
        return filtered
    }

    mutating func updateActivePinnedHosts(_ hosts: [String]) {
        activePinnedHosts = Set(hosts.map { PinnedHost.normalized($0) }.filter { !$0.isEmpty })
    }

    mutating func updateActivePinnedApps(_ appIDs: [String]) {
        activePinnedApps = Set(appIDs.map { FlowClientApp.normalizedID($0) }.filter { !$0.isEmpty })
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

    final class Cache {
        private var entries: [String: CacheEntry] = [:]

        fileprivate func projection(for flow: MitmFlow) -> FlowProjection {
            let source = ProjectionSource(flow: flow)
            if let entry = entries[flow.id], entry.source == source {
                return entry.projection
            }

            let projection = FlowProjection(flow: flow)
            entries[flow.id] = CacheEntry(source: source, projection: projection)
            return projection
        }

        fileprivate func retain(flowIDs: Set<String>) {
            entries = entries.filter { flowIDs.contains($0.key) }
        }

        private struct CacheEntry {
            let source: ProjectionSource
            let projection: FlowProjection
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
    var appTerms: [String] = []
    var excludedAppTerms: [String] = []
    var methods: Set<String> = []
    var excludedMethods: Set<String> = []
    var statusPredicate: ((Int) -> Bool)?
    var contentTypeTerms: [String] = []
    var excludedContentTypeTerms: [String] = []
    var protocolTerms: [String] = []
    var excludedProtocolTerms: [String] = []
    var operationTerms: [String] = []

    var isEmpty: Bool {
        keywords.isEmpty &&
            excludedKeywords.isEmpty &&
            hostTerms.isEmpty &&
            pathTerms.isEmpty &&
            urlTerms.isEmpty &&
            clientTerms.isEmpty &&
            excludedClientTerms.isEmpty &&
            appTerms.isEmpty &&
            excludedAppTerms.isEmpty &&
            methods.isEmpty &&
            excludedMethods.isEmpty &&
            statusPredicate == nil &&
            contentTypeTerms.isEmpty &&
            excludedContentTypeTerms.isEmpty &&
            protocolTerms.isEmpty &&
            excludedProtocolTerms.isEmpty &&
            operationTerms.isEmpty
    }

    func matches(_ flow: FlowProjection) -> Bool {
        if isEmpty { return true }

        let request = flow.request
        let response = flow.response

        let host = flow.host
        let path = flow.path
        let urlLowercased = flow.urlLowercased
        let method = flow.method
        let status = response?.status
        let clientIP = flow.clientIP
        let appHaystack = flow.appHaystack

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

        for term in appTerms where !term.isEmpty {
            if !appHaystack.localizedStandardContains(term) { return false }
        }
        for term in excludedAppTerms where !term.isEmpty {
            if appHaystack.localizedStandardContains(term) { return false }
        }

        let contentType = flow.responseContentType
        for term in contentTypeTerms where !term.isEmpty {
            if !Self.matchesContentType(term: term, headerValue: contentType, responseBody: response?.body) { return false }
        }
        for term in excludedContentTypeTerms where !term.isEmpty {
            if Self.matchesContentType(term: term, headerValue: contentType, responseBody: response?.body) { return false }
        }

        if !protocolTerms.isEmpty || !excludedProtocolTerms.isEmpty || !operationTerms.isEmpty {
            let inspections = flow.inspections
            let protocolNames = inspections.flatMap { [$0.kind.rawValue.lowercased(), $0.kind.displayName.lowercased()] }
            let operations = inspections.compactMap(\.summary).map { $0.lowercased() }

            for term in protocolTerms where !term.isEmpty {
                if !protocolNames.contains(where: { $0.localizedStandardContains(term) }) { return false }
            }
            for term in excludedProtocolTerms where !term.isEmpty {
                if protocolNames.contains(where: { $0.localizedStandardContains(term) }) { return false }
            }
            for term in operationTerms where !term.isEmpty {
                if !operations.contains(where: { $0.localizedStandardContains(term) }) { return false }
            }
        }

        if !keywords.isEmpty || !excludedKeywords.isEmpty {
            let haystack = flow.keywordHaystack

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
           query.appTerms.isEmpty, query.excludedAppTerms.isEmpty,
           query.methods.isEmpty, query.excludedMethods.isEmpty,
           query.statusPredicate == nil,
           query.contentTypeTerms.isEmpty, query.excludedContentTypeTerms.isEmpty,
           query.protocolTerms.isEmpty, query.excludedProtocolTerms.isEmpty,
           query.operationTerms.isEmpty {
            return FlowQuery()
        }

        query.keywords = query.keywords.filter { !$0.isEmpty }
        query.excludedKeywords = query.excludedKeywords.filter { !$0.isEmpty }
        query.clientTerms = query.clientTerms.filter { !$0.isEmpty }
        query.excludedClientTerms = query.excludedClientTerms.filter { !$0.isEmpty }
        query.appTerms = query.appTerms.filter { !$0.isEmpty }
        query.excludedAppTerms = query.excludedAppTerms.filter { !$0.isEmpty }
        query.protocolTerms = query.protocolTerms.filter { !$0.isEmpty }
        query.excludedProtocolTerms = query.excludedProtocolTerms.filter { !$0.isEmpty }
        query.operationTerms = query.operationTerms.filter { !$0.isEmpty }
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
        case "app", "bundle", "bundleid", "bundle-id":
            let term = normalizedValue.lowercased()
            if excluded {
                excludedAppTerms.append(term)
            } else {
                appTerms.append(term)
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
        case "protocol", "proto":
            let term = normalizedValue.lowercased()
            if excluded {
                excludedProtocolTerms.append(term)
            } else {
                protocolTerms.append(term)
            }
        case "operation", "operation-name", "graphql-operation":
            guard !excluded else { return }
            operationTerms.append(normalizedValue.lowercased())
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

private struct ProjectionSource: Equatable {
    let request: MitmFlow.Request?
    let response: MitmFlow.Response?
    let client: MitmFlow.Client?
    let clientApp: FlowClientApp?

    init(flow: MitmFlow) {
        request = flow.request
        response = flow.response
        client = flow.client
        clientApp = flow.clientApp
    }
}

private final class FlowProjection {
    let request: MitmFlow.Request?
    let response: MitmFlow.Response?
    let clientIP: String
    let appHaystack: String
    let urlLowercased: String
    let host: String
    let path: String
    let method: String
    let responseContentType: String

    lazy var inspections: [ProtocolInspectionResult] = {
        [
            ProtocolInspector.inspect(body: request?.body, headers: request?.headers ?? [:]),
            ProtocolInspector.inspect(body: response?.body, headers: response?.headers ?? [:])
        ].compactMap { $0 }
    }()

    lazy var keywordHaystack: String = {
        [
            urlLowercased,
            method.lowercased(),
            host,
            path,
            Self.allHeadersLowercased(request?.headers),
            Self.allHeadersLowercased(response?.headers),
            request?.body?.lowercased() ?? "",
            response?.body?.lowercased() ?? ""
        ].joined(separator: " ")
    }()

    init(flow: MitmFlow) {
        request = flow.request
        response = flow.response
        clientIP = flow.clientIP.lowercased()
        appHaystack = [
            flow.clientApp?.displayName.lowercased() ?? "",
            flow.clientApp?.bundleIdentifier?.lowercased() ?? "",
            flow.clientApp?.id.lowercased() ?? ""
        ].joined(separator: " ")

        let urlString = flow.request?.url ?? ""
        let url = URLComponents(string: urlString)
        urlLowercased = urlString.lowercased()
        host = PinnedHost.normalized(url?.host ?? urlString)
        path = (url?.path ?? "").lowercased()
        method = (flow.request?.method ?? "").uppercased()
        responseContentType = Self.headerValue("content-type", in: flow.response?.headers)?.lowercased() ?? ""
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
}
