import AppKit
import Foundation

@MainActor
final class SelectiveCaptureService {
    func launchApplication(
        at applicationURL: URL,
        configuration: SelectiveCaptureConfiguration
    ) async throws -> NSRunningApplication {
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.createsNewApplicationInstance = true
        openConfiguration.environment = SelectiveCaptureEnvironment.make(configuration: configuration)
        openConfiguration.arguments = SelectiveCaptureEnvironment.arguments(
            configuration: configuration,
            applicationSupportDirectory: URL.applicationSupportDirectory.appending(path: "FRTMProxy")
        )
        return try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: openConfiguration)
    }

    func launchCommand(
        executableURL: URL,
        arguments: [String],
        configuration: SelectiveCaptureConfiguration
    ) throws -> Process {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/") else {
            throw SelectiveCaptureError.invalidExecutable
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = SelectiveCaptureEnvironment.make(configuration: configuration)
        try process.run()
        return process
    }
}
