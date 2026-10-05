import Foundation
import Observation

@MainActor @Observable
final class JSONBodyQueryModel {
    private(set) var output = ""
    private(set) var count = 0
    private(set) var error: String?
    private(set) var isSearching = false
    private var task: Task<Void, Never>?

    func search(body: String, query: String, mode: JSONBodyQuery.Mode) {
        cancel()
        output = ""
        error = nil
        count = 0
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        task = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let worker = Task.detached(priority: .userInitiated) { try JSONBodyQuery.evaluate(body: body, query: query, mode: mode) }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                output = result.text
                count = result.count
                isSearching = false
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isSearching = false
            }
        }
    }

    func cancel() { task?.cancel(); task = nil; isSearching = false }
}
