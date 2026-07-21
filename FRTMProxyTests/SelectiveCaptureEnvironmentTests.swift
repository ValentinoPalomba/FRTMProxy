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
    func chromiumArguments() {
        let configuration = SelectiveCaptureConfiguration(proxyPort: 8080, profile: .chromium)
        let arguments = SelectiveCaptureEnvironment.arguments(
            configuration: configuration,
            applicationSupportDirectory: URL(filePath: "/tmp/FRTMProxy", directoryHint: .isDirectory)
        )
        #expect(arguments.contains("--proxy-server=http://127.0.0.1:8080"))
        #expect(arguments.contains(where: { $0.hasPrefix("--user-data-dir=/tmp/FRTMProxy/SelectiveCapture/") }))
    }
}
