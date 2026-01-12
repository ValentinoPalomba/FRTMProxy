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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([MapRule].self, from: data)
        } catch {
            NSLog("Failed to load rules: \(error)")
            return []
        }
    }

    func save(rules: [MapRule]) {
        do {
            let data = try encoder.encode(rules)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save rules: \(error)")
        }
    }
}
