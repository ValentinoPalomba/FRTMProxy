import Foundation

struct SelectiveCaptureTermination: Equatable, Sendable {
    let exitCode: Int32?
}

@MainActor
protocol SelectiveCaptureRunningTarget: AnyObject {
    var displayName: String { get }

    func waitForTermination() async -> SelectiveCaptureTermination
}

@MainActor
protocol SelectiveCaptureLaunching: AnyObject {
    func launchApplication(
        at applicationURL: URL,
        configuration: SelectiveCaptureConfiguration
    ) async throws -> any SelectiveCaptureRunningTarget

    func launchCommand(
        executableURL: URL,
        arguments: [String],
        configuration: SelectiveCaptureConfiguration
    ) throws -> any SelectiveCaptureRunningTarget
}
