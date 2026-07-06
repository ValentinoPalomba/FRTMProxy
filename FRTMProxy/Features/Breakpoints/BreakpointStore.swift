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
        switch CodableFileStore.load([FlowBreakpointRule].self, from: fileURL, decoder: decoder) {
        case .loaded(let breakpoints):
            return breakpoints
        case .missing, .corrupted:
            return []
        }
    }

    func save(breakpoints: [FlowBreakpointRule]) {
        do {
            try CodableFileStore.save(breakpoints, to: fileURL, encoder: encoder)
        } catch {
            NSLog("Failed to save breakpoints: \(error)")
        }
    }
}
