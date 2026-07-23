import AppKit
import Foundation

@MainActor
final class SelectiveCaptureService: SelectiveCaptureLaunching {
    func launchApplication(
        at applicationURL: URL,
        configuration: SelectiveCaptureConfiguration
    ) async throws -> any SelectiveCaptureRunningTarget {
        try SelectiveCaptureError.validateApplication(at: applicationURL)

        let launchPlan = SelectiveCaptureEnvironment.launchPlan(
            configuration: configuration,
            applicationSupportDirectory: URL.applicationSupportDirectory.appending(path: "FRTMProxy")
        )
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.createsNewApplicationInstance = true
        openConfiguration.environment = SelectiveCaptureEnvironment.make(configuration: configuration)
        openConfiguration.arguments = launchPlan.arguments

        do {
            let application = try await NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: openConfiguration
            )
            return SelectiveCaptureApplicationTarget(
                application: application,
                fallbackDisplayName: applicationURL.deletingPathExtension().lastPathComponent,
                temporaryProfileDirectory: launchPlan.temporaryProfileDirectory
            )
        } catch {
            Self.removeTemporaryProfile(at: launchPlan.temporaryProfileDirectory)
            throw error
        }
    }

    func launchCommand(
        executableURL: URL,
        arguments: [String],
        configuration: SelectiveCaptureConfiguration
    ) throws -> any SelectiveCaptureRunningTarget {
        try SelectiveCaptureError.validateExecutable(at: executableURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = SelectiveCaptureEnvironment.make(configuration: configuration)
        let runningTarget = SelectiveCaptureCommandTarget(
            process: process,
            displayName: executableURL.lastPathComponent
        )
        try process.run()
        return runningTarget
    }

    fileprivate static func removeTemporaryProfile(at url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class SelectiveCaptureApplicationTarget: SelectiveCaptureRunningTarget {
    let displayName: String

    private let application: NSRunningApplication
    private let temporaryProfileDirectory: URL?

    init(
        application: NSRunningApplication,
        fallbackDisplayName: String,
        temporaryProfileDirectory: URL?
    ) {
        self.application = application
        self.displayName = application.localizedName ?? fallbackDisplayName
        self.temporaryProfileDirectory = temporaryProfileDirectory
    }

    func waitForTermination() async -> SelectiveCaptureTermination {
        defer {
            SelectiveCaptureService.removeTemporaryProfile(at: temporaryProfileDirectory)
        }
        guard !application.isTerminated else {
            return SelectiveCaptureTermination(exitCode: nil)
        }

        let notifications = NSWorkspace.shared.notificationCenter.notifications(
            named: NSWorkspace.didTerminateApplicationNotification
        )
        guard !application.isTerminated else {
            return SelectiveCaptureTermination(exitCode: nil)
        }

        for await notification in notifications {
            guard
                let terminatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                terminatedApplication.processIdentifier == application.processIdentifier
            else {
                continue
            }
            return SelectiveCaptureTermination(exitCode: nil)
        }
        return SelectiveCaptureTermination(exitCode: nil)
    }
}

@MainActor
private final class SelectiveCaptureCommandTarget: SelectiveCaptureRunningTarget {
    let displayName: String

    private let process: Process
    private let terminations: AsyncStream<Int32>

    init(process: Process, displayName: String) {
        self.process = process
        self.displayName = displayName
        self.terminations = AsyncStream { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.yield(terminatedProcess.terminationStatus)
                continuation.finish()
            }
        }
    }

    func waitForTermination() async -> SelectiveCaptureTermination {
        guard process.isRunning else {
            return SelectiveCaptureTermination(exitCode: process.terminationStatus)
        }
        for await exitCode in terminations {
            return SelectiveCaptureTermination(exitCode: exitCode)
        }
        return SelectiveCaptureTermination(exitCode: process.terminationStatus)
    }
}
