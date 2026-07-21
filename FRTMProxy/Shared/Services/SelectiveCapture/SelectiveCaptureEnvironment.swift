import Foundation

enum SelectiveCaptureEnvironment {
    static func make(
        configuration: SelectiveCaptureConfiguration,
        inheriting base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["HTTP_PROXY"] = configuration.proxyURL
        environment["HTTPS_PROXY"] = configuration.proxyURL
        environment["ALL_PROXY"] = configuration.proxyURL
        environment["http_proxy"] = configuration.proxyURL
        environment["https_proxy"] = configuration.proxyURL
        environment["all_proxy"] = configuration.proxyURL

        if let certificateURL = configuration.certificateURL {
            environment["SSL_CERT_FILE"] = certificateURL.path
            environment["NODE_EXTRA_CA_CERTS"] = certificateURL.path
            environment["REQUESTS_CA_BUNDLE"] = certificateURL.path
            environment["CURL_CA_BUNDLE"] = certificateURL.path
        }
        return environment
    }

    static func arguments(
        configuration: SelectiveCaptureConfiguration,
        applicationSupportDirectory: URL
    ) -> [String] {
        switch configuration.profile {
        case .standardEnvironment:
            return []
        case .chromium, .electron:
            let profileDirectory = applicationSupportDirectory
                .appending(path: "SelectiveCapture", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            return [
                "--proxy-server=\(configuration.proxyURL)",
                "--user-data-dir=\(profileDirectory.path)",
                "--no-first-run"
            ]
        }
    }
}
