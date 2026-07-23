import Foundation
import Testing
@testable import FRTMProxy

@Suite("Selective capture environment")
struct SelectiveCaptureEnvironmentTests {
    @Test("Configura proxy e CA senza perdere l'ambiente ereditato")
    func environment() {
        let configuration = SelectiveCaptureConfiguration(
            proxyPort: 9090,
            certificateURL: URL(filePath: "/tmp/ca.pem")
        )
        let environment = SelectiveCaptureEnvironment.make(configuration: configuration, inheriting: ["PATH": "/bin"])
        #expect(environment["PATH"] == "/bin")
        #expect(environment["HTTPS_PROXY"] == "http://127.0.0.1:9090")
        #expect(environment["NODE_EXTRA_CA_CERTS"] == "/tmp/ca.pem")
    }

    @Test("Chromium riceve un profilo isolato e il proxy esplicito")
    func chromiumArguments() throws {
        let configuration = SelectiveCaptureConfiguration(proxyPort: 8080, profile: .chromium)
        let profileIdentifier = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        let plan = SelectiveCaptureEnvironment.launchPlan(
            configuration: configuration,
            applicationSupportDirectory: URL(filePath: "/tmp/FRTMProxy", directoryHint: .isDirectory),
            profileIdentifier: profileIdentifier
        )
        #expect(plan.arguments.contains("--proxy-server=http://127.0.0.1:8080"))
        #expect(
            plan.arguments.contains(
                "--user-data-dir=/tmp/FRTMProxy/SelectiveCapture/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            )
        )
        #expect(
            plan.temporaryProfileDirectory?.path
                == "/tmp/FRTMProxy/SelectiveCapture/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )
    }

    @Test("Il profilo standard non crea risorse temporanee")
    func standardArguments() {
        let plan = SelectiveCaptureEnvironment.launchPlan(
            configuration: SelectiveCaptureConfiguration(proxyPort: 8080),
            applicationSupportDirectory: URL(filePath: "/tmp/FRTMProxy", directoryHint: .isDirectory)
        )
        #expect(plan.arguments.isEmpty)
        #expect(plan.temporaryProfileDirectory == nil)
    }

    @Test("Rifiuta un comando che non è eseguibile")
    func rejectsNonExecutableCommand() throws {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try Data().write(to: temporaryFile)
        defer { try? FileManager.default.removeItem(at: temporaryFile) }

        #expect(throws: SelectiveCaptureError.self) {
            try SelectiveCaptureError.validateExecutable(at: temporaryFile)
        }
    }
}

@Suite("Selective capture lifecycle")
@MainActor
struct SelectiveCaptureLifecycleTests {
    @Test("Mantiene il target in esecuzione e pubblica la terminazione")
    func runningAndTermination() async {
        let target = SelectiveCaptureTestRunningTarget(displayName: "echo")
        let launcher = SelectiveCaptureTestLauncher(target: target)
        let model = SelectiveCaptureLaunchModel(launcher: launcher)

        model.launchCommand(
            executableURL: URL(filePath: "/bin/echo"),
            arguments: ["hello"],
            configuration: SelectiveCaptureConfiguration(proxyPort: 8080)
        )

        #expect(model.state == .running(displayName: "echo"))
        #expect(launcher.commandArguments == ["hello"])

        target.finish(exitCode: 0)
        await Task.yield()
        await Task.yield()

        #expect(model.state == .terminated(displayName: "echo", exitCode: 0))
    }

    @Test("Espone un errore di lancio senza restare bloccato")
    func launchFailure() {
        let launcher = SelectiveCaptureTestLauncher(
            target: SelectiveCaptureTestRunningTarget(displayName: "echo"),
            error: SelectiveCaptureTestError.launchFailed
        )
        let model = SelectiveCaptureLaunchModel(launcher: launcher)

        model.launchCommand(
            executableURL: URL(filePath: "/bin/echo"),
            arguments: [],
            configuration: SelectiveCaptureConfiguration(proxyPort: 8080)
        )

        #expect(model.state == .failed(message: "Launch failed"))
        #expect(!model.isActive)
    }
}

private enum SelectiveCaptureTestError: LocalizedError {
    case launchFailed

    var errorDescription: String? {
        "Launch failed"
    }
}

@MainActor
private final class SelectiveCaptureTestLauncher: SelectiveCaptureLaunching {
    private let target: SelectiveCaptureTestRunningTarget
    private let error: Error?

    private(set) var commandArguments: [String]?

    init(target: SelectiveCaptureTestRunningTarget, error: Error? = nil) {
        self.target = target
        self.error = error
    }

    func launchApplication(
        at applicationURL: URL,
        configuration: SelectiveCaptureConfiguration
    ) async throws -> any SelectiveCaptureRunningTarget {
        if let error {
            throw error
        }
        return target
    }

    func launchCommand(
        executableURL: URL,
        arguments: [String],
        configuration: SelectiveCaptureConfiguration
    ) throws -> any SelectiveCaptureRunningTarget {
        commandArguments = arguments
        if let error {
            throw error
        }
        return target
    }
}

@MainActor
private final class SelectiveCaptureTestRunningTarget: SelectiveCaptureRunningTarget {
    let displayName: String

    private var termination: SelectiveCaptureTermination?
    private var continuation: CheckedContinuation<SelectiveCaptureTermination, Never>?

    init(displayName: String) {
        self.displayName = displayName
    }

    func waitForTermination() async -> SelectiveCaptureTermination {
        if let termination {
            return termination
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(exitCode: Int32?) {
        let termination = SelectiveCaptureTermination(exitCode: exitCode)
        self.termination = termination
        continuation?.resume(returning: termination)
        continuation = nil
    }
}
