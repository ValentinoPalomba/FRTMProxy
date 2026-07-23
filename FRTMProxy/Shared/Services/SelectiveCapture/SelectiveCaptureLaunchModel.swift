import Foundation
import Observation

@MainActor
@Observable
final class SelectiveCaptureLaunchModel {
    private(set) var state: SelectiveCaptureLaunchState = .idle

    private let launcher: any SelectiveCaptureLaunching
    private var runningTarget: (any SelectiveCaptureRunningTarget)?

    init(launcher: any SelectiveCaptureLaunching) {
        self.launcher = launcher
    }

    var isActive: Bool {
        state.isActive
    }

    func launchApplication(
        at applicationURL: URL,
        configuration: SelectiveCaptureConfiguration
    ) async {
        guard !state.isActive else { return }
        state = .launching

        do {
            try SelectiveCaptureError.validateApplication(at: applicationURL)
            let target = try await launcher.launchApplication(
                at: applicationURL,
                configuration: configuration
            )
            observe(target)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func launchCommand(
        executableURL: URL,
        arguments: [String],
        configuration: SelectiveCaptureConfiguration
    ) {
        guard !state.isActive else { return }
        state = .launching

        do {
            try SelectiveCaptureError.validateExecutable(at: executableURL)
            let target = try launcher.launchCommand(
                executableURL: executableURL,
                arguments: arguments,
                configuration: configuration
            )
            observe(target)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func resetStatus() {
        guard !state.isActive else { return }
        state = .idle
    }

    private func observe(_ target: any SelectiveCaptureRunningTarget) {
        runningTarget = target
        state = .running(displayName: target.displayName)

        Task { [weak self, target] in
            let termination = await target.waitForTermination()
            guard let self, self.runningTarget === target else { return }
            self.runningTarget = nil
            self.state = .terminated(
                displayName: target.displayName,
                exitCode: termination.exitCode
            )
        }
    }
}
