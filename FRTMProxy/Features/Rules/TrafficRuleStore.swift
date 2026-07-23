import Foundation

protocol TrafficRuleStoreProtocol {
    func loadRules() throws -> [TrafficRule]
    func save(rules: [TrafficRule]) throws
}

/// Persists the unified rule document and performs a one-time copy-on-read import.
/// Legacy files are only read: migration never renames, deletes, or rewrites them.
final class TrafficRuleStore: TrafficRuleStoreProtocol {
    enum StoreError: Error {
        case unsupportedSchemaVersion(Int)
        case unreadableLegacyFile(URL, Error)
    }

    private let directoryURL: URL
    private let fileURL: URL
    private let legacyMapRuleFilenames: [String]
    private let legacyBreakpointFilename: String
    private let legacyScriptFilename: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        directoryURL: URL? = nil,
        filename: String = "traffic-rules.json",
        legacyMapRuleFilenames: [String] = ["map_rules.json", "rules.json"],
        legacyBreakpointFilename: String = "breakpoints.json",
        legacyScriptFilename: String = "scripts.json"
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.directoryURL = directoryURL ?? base.appending(path: "FRTMProxy", directoryHint: .isDirectory)
        fileURL = self.directoryURL.appending(path: filename)
        self.legacyMapRuleFilenames = legacyMapRuleFilenames
        self.legacyBreakpointFilename = legacyBreakpointFilename
        self.legacyScriptFilename = legacyScriptFilename
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadRules() throws -> [TrafficRule] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let document = try decoder.decode(TrafficRuleDocument.self, from: Data(contentsOf: fileURL))
            guard document.schemaVersion <= TrafficRuleDocument.currentSchemaVersion else {
                throw StoreError.unsupportedSchemaVersion(document.schemaVersion)
            }
            if let unsupported = document.rules.first(where: {
                $0.schemaVersion > TrafficRule.currentSchemaVersion
            }) {
                throw StoreError.unsupportedSchemaVersion(unsupported.schemaVersion)
            }
            return document.rules
        }

        let imported = try importLegacyRules()
        guard !imported.isEmpty else { return [] }
        try save(rules: imported)
        return imported
    }

    func save(rules: [TrafficRule]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(TrafficRuleDocument(rules: rules))
        try data.write(to: fileURL, options: .atomic)
    }

    private func importLegacyRules() throws -> [TrafficRule] {
        var rules: [TrafficRule] = []

        if let mapURL = legacyMapRuleFilenames
            .map({ directoryURL.appending(path: $0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            let legacy: [LegacyMapRule] = try decodeLegacy([LegacyMapRule].self, from: mapURL)
            for item in legacy {
                rules.append(item.trafficRule(priority: rules.count))
            }
        }

        let breakpointURL = directoryURL.appending(path: legacyBreakpointFilename)
        if FileManager.default.fileExists(atPath: breakpointURL.path) {
            let legacy: [LegacyBreakpointRule] = try decodeLegacy([LegacyBreakpointRule].self, from: breakpointURL)
            for item in legacy {
                rules.append(item.trafficRule(priority: rules.count))
            }
        }

        let scriptURL = directoryURL.appending(path: legacyScriptFilename)
        if FileManager.default.fileExists(atPath: scriptURL.path) {
            let legacy: [LegacyScriptRule] = try decodeLegacy([LegacyScriptRule].self, from: scriptURL)
            for item in legacy {
                rules.append(item.trafficRule(priority: rules.count))
            }
        }
        return rules
    }

    private func decodeLegacy<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            throw StoreError.unreadableLegacyFile(url, error)
        }
    }
}

private struct LegacyMapRule: Decodable {
    struct Request: Decodable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: String?
    }

    let key: String
    let host: String
    let path: String
    let scheme: String?
    let request: Request?
    let body: String
    let status: Int
    let headers: [String: String]
    let isEnabled: Bool

    func trafficRule(priority: Int) -> TrafficRule {
        let contentType = request?.headers.first {
            $0.key.caseInsensitiveCompare("content-type") == .orderedSame
        }?.value
        let matcher = TrafficRuleMatcher(
            scheme: scheme.map { .init(value: $0, isCaseSensitive: false) },
            host: Self.endpointPattern(host, caseSensitive: false),
            path: Self.endpointPattern(path.isEmpty ? "/" : path, caseSensitive: true),
            method: request.map { .init(value: TrafficRuleCanonicalizer.method($0.method), isCaseSensitive: false) },
            query: request.map { .init(value: TrafficRuleCanonicalizer.query(from: $0.url)) },
            body: request.map { .init(value: TrafficRuleCanonicalizer.body($0.body, contentType: contentType)) }
        )
        return TrafficRule(
            id: TrafficRuleCanonicalizer.legacyIdentifier(for: "map:\(key)"),
            name: "Map Local · \(key)",
            isEnabled: isEnabled,
            priority: priority,
            matcher: matcher,
            actions: [.mock(.init(
                id: TrafficRuleCanonicalizer.legacyIdentifier(for: "map-action:\(key)"),
                status: status,
                headers: headers,
                body: body
            ))]
        )
    }

    fileprivate static func endpointPattern(_ value: String, caseSensitive: Bool) -> TrafficRuleTextPattern {
        .init(
            value: value,
            mode: value.contains("*") || value.contains("?") ? .wildcard : .exact,
            isCaseSensitive: caseSensitive
        )
    }
}

private struct LegacyBreakpointRule: Decodable {
    let key: String
    let host: String
    let path: String
    let scheme: String?
    let interceptRequest: Bool
    let interceptResponse: Bool
    let isEnabled: Bool

    func trafficRule(priority: Int) -> TrafficRule {
        TrafficRule(
            id: TrafficRuleCanonicalizer.legacyIdentifier(for: "breakpoint:\(key)"),
            name: "Breakpoint · \(key)",
            isEnabled: isEnabled,
            priority: priority,
            matcher: .init(
                scheme: scheme.map { .init(value: $0, isCaseSensitive: false) },
                host: LegacyMapRule.endpointPattern(host, caseSensitive: false),
                path: LegacyMapRule.endpointPattern(path.isEmpty ? "/" : path, caseSensitive: true)
            ),
            actions: [
                .breakpoint(.init(
                    id: TrafficRuleCanonicalizer.legacyIdentifier(for: "breakpoint-action:\(key)"),
                    request: interceptRequest,
                    response: interceptResponse
                ))
            ]
        )
    }
}

private struct LegacyScriptRule: Decodable {
    let id: UUID
    let name: String
    let host: String
    let path: String
    let code: String
    let isEnabled: Bool

    func trafficRule(priority: Int) -> TrafficRule {
        let hostPattern: TrafficRuleTextPattern? = host.isEmpty
            ? nil
            : .init(value: "*\(host)*", mode: .wildcard, isCaseSensitive: false)
        let pathPattern: TrafficRuleTextPattern? = path.isEmpty
            ? nil
            : .init(value: "\(path)*", mode: .wildcard)
        return TrafficRule(
            id: id,
            name: name.isEmpty ? "Script" : name,
            isEnabled: isEnabled,
            priority: priority,
            matcher: .init(host: hostPattern, path: pathPattern),
            actions: [.script(.init(id: id, source: code, responseOnly: true))]
        )
    }
}
