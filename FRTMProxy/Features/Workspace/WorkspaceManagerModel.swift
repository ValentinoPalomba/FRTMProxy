import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceManagerModel {
    private let service: WorkspaceBundleService

    private(set) var importPlan: WorkspaceImportPlan?
    private(set) var importResult: WorkspaceImportResult?
    private(set) var isWorking = false
    private(set) var lastExportURL: URL?
    var errorMessage: String?

    init(service: WorkspaceBundleService = WorkspaceBundleService()) {
        self.service = service
    }

    func prepareImport(from url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            importPlan = try await service.importPlan(from: url)
            importResult = nil
            errorMessage = nil
        } catch {
            importPlan = nil
            importResult = nil
            errorMessage = error.localizedDescription
        }
    }

    func applyImport(
        using apply: (WorkspaceImportPlan) throws -> WorkspaceImportResult
    ) {
        guard !isWorking, let importPlan else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            importResult = try apply(importPlan)
            errorMessage = nil
        } catch {
            importResult = nil
            errorMessage = error.localizedDescription
        }
    }

    func discardImport() {
        importPlan = nil
        importResult = nil
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
