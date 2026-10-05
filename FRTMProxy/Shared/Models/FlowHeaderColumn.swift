import Foundation

struct FlowHeaderColumn: Identifiable, Codable, Equatable, Sendable {
    static let dataKey = "inspector.headerColumns"
    static let sortKey = "inspector.headerSortID"
    static let directionKey = "inspector.sortAscending"
    enum Phase: String, Codable, CaseIterable, Sendable { case request = "Request", response = "Response" }
    var id = UUID()
    var phase: Phase
    var name: String
    var title: String { "\(phase.rawValue): \(name)" }

    static func decode(_ data: Data) throws -> [Self] {
        if data.isEmpty { return [] }
        guard data.count <= 32 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let columns = try JSONDecoder().decode([Self].self, from: data)
        try validate(columns)
        return columns
    }
    static func validate(_ columns: [Self]) throws {
        guard columns.count <= 8, Set(columns.map(\.id)).count == columns.count,
              columns.allSatisfy({ $0.name.utf8.count <= 128 && HTTPHeaderField.isValidName($0.name) }),
              Set(columns.map { $0.phase.rawValue + ":" + $0.name.lowercased() }).count == columns.count else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
    }
    func values(in flow: MitmFlow) -> [String] {
        let fields = phase == .request ? flow.request?.headerFields : flow.response?.headerFields
        if let fields { return fields.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value) }
        let legacy = phase == .request ? flow.request?.headers : flow.response?.headers
        return (legacy ?? [:]).sorted { $0.key < $1.key }.filter { $0.key.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
    func displayValue(in flow: MitmFlow) -> String? {
        let values = values(in: flow)
        guard !values.isEmpty else { return nil }
        // ponytail: bounded cell/sort preview; use the inspector for complete header values.
        var lines = values.prefix(8).map {
            let preview = String($0.prefix(257))
            return String(preview.prefix(256)) + (preview.count > 256 ? "…" : "")
        }
        if values.count > 8 { lines.append("… (\(values.count) occurrences)") }
        return lines.joined(separator: "\n")
    }
    func sorted(_ flows: [MitmFlow], ascending: Bool) -> [MitmFlow] {
        let keys = Dictionary(uniqueKeysWithValues: flows.map { ($0.id, displayValue(in: $0)) })
        return flows.sorted { a, b in
            let left = keys[a.id] ?? nil, right = keys[b.id] ?? nil
            if left == right { return a.id < b.id }
            if left == nil { return ascending }
            if right == nil { return !ascending }
            let order = (left ?? "").localizedStandardCompare(right ?? "")
            if order == .orderedSame { return a.id < b.id }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}
