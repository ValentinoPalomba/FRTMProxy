import Foundation

final class ScriptStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "scripts.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("FRTMProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    func load() -> [ScriptRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([ScriptRule].self, from: data)
        } catch {
            NSLog("ScriptStore: failed to load: \(error)")
            return []
        }
    }

    func save(_ rules: [ScriptRule]) {
        do {
            let data = try encoder.encode(rules)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ScriptStore: failed to save: \(error)")
        }
    }
}
