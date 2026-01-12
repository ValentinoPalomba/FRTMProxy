import Foundation

final class CollectionRecorder {
    struct Session {
        let id: UUID
        let name: String
        let startedAt: Date
        private(set) var rules: [String: MapRule]

        init(id: UUID = UUID(), name: String, startedAt: Date = Date()) {
            self.id = id
            self.name = name
            self.startedAt = startedAt
            self.rules = [:]
        }

        mutating func record(rule: MapRule) {
            rules[rule.key] = rule
        }

        var sortedRules: [MapRule] {
            Array(rules.values).sorted(by: { $0.key < $1.key })
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
