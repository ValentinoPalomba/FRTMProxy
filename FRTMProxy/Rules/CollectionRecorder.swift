import Foundation

final class CollectionRecorder {
    struct Session {
        let id: UUID
        let name: String
        let startedAt: Date
        private(set) var rules: [String: MapRule]
        private(set) var orderedKeys: [String]

        init(id: UUID = UUID(), name: String, startedAt: Date = Date()) {
            self.id = id
            self.name = name
            self.startedAt = startedAt
            self.rules = [:]
            self.orderedKeys = []
        }

        mutating func record(rule: MapRule) {
            if rules[rule.key] == nil {
                orderedKeys.append(rule.key)
            }
            rules[rule.key] = rule
        }

        var sortedRules: [MapRule] {
            orderedKeys.compactMap { rules[$0] }
        }

        func makeCollection() -> MapCollection {
            MapCollection(
                id: id,
                name: name,
                createdAt: startedAt,
                isEnabled: false,
                enabledAt: nil,
                rules: sortedRules
            )
        }
    }

    private var session: Session?

    var isRecording: Bool {
        session != nil
    }

    var recordingName: String? {
        session?.name
    }

    func currentRules() -> [MapRule] {
        session?.sortedRules ?? []
    }

    func start(name: String) {
        session = Session(name: name)
    }

    func record(rule: MapRule) {
        guard var current = session else { return }
        current.record(rule: rule)
        session = current
    }

    func stopAndCreateCollection() -> MapCollection? {
        defer { session = nil }
        return session?.makeCollection()
    }

    func discard() {
        session = nil
    }
}
