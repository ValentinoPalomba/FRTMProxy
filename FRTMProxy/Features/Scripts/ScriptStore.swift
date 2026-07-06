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
        switch CodableFileStore.load([ScriptRule].self, from: fileURL, decoder: decoder) {
        case .loaded(let rules):
            return rules
        case .missing, .corrupted:
            return []
        }
    }

    func save(_ rules: [ScriptRule]) {
        do {
            try CodableFileStore.save(rules, to: fileURL, encoder: encoder)
        } catch {
            NSLog("ScriptStore: failed to save: \(error)")
        }
    }
}
