import Foundation

struct SelectiveCaptureConfiguration: Codable, Equatable, Sendable {
    let proxyHost: String
    let proxyPort: Int
    let certificateURL: URL?
    let profile: CaptureLaunchProfile

    init(
        proxyHost: String = "127.0.0.1",
        proxyPort: Int,
        certificateURL: URL? = nil,
        profile: CaptureLaunchProfile = .standardEnvironment
    ) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.certificateURL = certificateURL
        self.profile = profile
    }

    var proxyURL: String {
        "http://\(proxyHost):\(proxyPort)"
    }
}
