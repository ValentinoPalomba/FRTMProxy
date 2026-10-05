import Foundation

struct SavedFocusSet: Codable, Identifiable, Equatable, Sendable {
    static let dataKey = "inspector.focusSets"
    static func decode(_ data: Data) throws -> [Self] {
        if data.isEmpty { return [] }
        guard data.count <= 256 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let sets = try JSONDecoder().decode([Self].self, from: data)
        try validate(sets)
        return sets
    }
    static func encode(_ sets: [Self]) throws -> Data {
        try validate(sets)
        let data = try JSONEncoder().encode(sets)
        guard data.count <= 256 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }
    static func validate(_ sets: [Self]) throws {
        guard sets.count <= 50, Set(sets.map(\.id)).count == sets.count else { throw CocoaError(.validationMissingMandatoryProperty) }
        var bytes = 0
        for scope in sets {
            let filter = scope.filter
            guard !scope.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  scope.name.utf8.count <= 128, filter.searchText.utf8.count <= 4096 else { throw CocoaError(.validationMissingMandatoryProperty) }
            bytes += scope.name.utf8.count + filter.searchText.utf8.count
            for values in [filter.activePinnedHosts, filter.activePinnedApps, filter.activeClientIPs] {
                guard values.count <= 128, values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else { throw CocoaError(.validationMissingMandatoryProperty) }
                bytes += values.reduce(0) { $0 + $1.utf8.count }
            }
            guard bytes <= 256 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        }
    }
    var id = UUID()
    var name: String
    var filter: FlowFilter
}
