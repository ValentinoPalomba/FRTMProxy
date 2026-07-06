import Foundation

protocol MapRuleStoreProtocol {
    func loadRules() -> [MapRule]
    func save(rules: [MapRule])
}

final class MapRuleStore: MapRuleStoreProtocol {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "rules.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("FRTMProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    func loadRules() -> [MapRule] {
        switch CodableFileStore.load([MapRule].self, from: fileURL, decoder: decoder) {
        case .loaded(let rules):
            return rules
        case .missing, .corrupted:
            return []
        }
    }

    func save(rules: [MapRule]) {
        do {
            try CodableFileStore.save(rules, to: fileURL, encoder: encoder)
        } catch {
            NSLog("Failed to save rules: \(error)")
        }
    }
}
