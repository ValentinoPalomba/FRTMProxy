import Foundation

protocol BreakpointStoreProtocol {
    func loadBreakpoints() -> [FlowBreakpointRule]
    func save(breakpoints: [FlowBreakpointRule])
}

final class FlowBreakpointStore: BreakpointStoreProtocol {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "breakpoints.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("FRTMProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
    }

    func loadBreakpoints() -> [FlowBreakpointRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([FlowBreakpointRule].self, from: data)
        } catch {
            NSLog("Failed to load breakpoints: \(error)")
            return []
        }
    }

    func save(breakpoints: [FlowBreakpointRule]) {
        do {
            let data = try encoder.encode(breakpoints)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save breakpoints: \(error)")
        }
    }
}
