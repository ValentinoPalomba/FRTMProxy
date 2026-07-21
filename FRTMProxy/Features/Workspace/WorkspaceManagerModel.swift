import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceManagerModel {
    private let service: WorkspaceBundleService

    private(set) var loadedBundle: WorkspaceBundle?
    private(set) var isWorking = false
    private(set) var lastExportURL: URL?
    var errorMessage: String?

    init(service: WorkspaceBundleService = WorkspaceBundleService()) {
        self.service = service
    }

    func importWorkspace(from url: URL) async -> WorkspaceBundle? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let bundle = try await service.importWorkspace(from: url)
            loadedBundle = bundle
            errorMessage = nil
            return bundle
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportWorkspace(_ bundle: WorkspaceBundle, toSelectedRoot url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            lastExportURL = try await service.export(bundle, toSelectedRoot: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
