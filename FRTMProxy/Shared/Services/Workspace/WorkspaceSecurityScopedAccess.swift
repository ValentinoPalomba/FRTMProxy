import Foundation

protocol WorkspaceSecurityScopedAccessing: Sendable {
    func withAccess<T>(to url: URL, perform operation: () throws -> T) throws -> T
}

struct WorkspaceSecurityScopedURLAccessor: WorkspaceSecurityScopedAccessing {
    private let requiresGrantedScope: Bool

    init(requiresGrantedScope: Bool = false) {
        self.requiresGrantedScope = requiresGrantedScope
    }

    func withAccess<T>(to url: URL, perform operation: () throws -> T) throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart || !requiresGrantedScope else {
            throw WorkspaceServiceError.securityScopedAccessDenied(url)
        }
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}

protocol WorkspaceExportCommitting: Sendable {
    func willCommitExport() throws
}

struct WorkspaceExportCommitHook: WorkspaceExportCommitting {
    func willCommitExport() throws { }
}
