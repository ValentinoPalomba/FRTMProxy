import Foundation
import Network

struct UpstreamProxyConfiguration: Codable, Equatable, Sendable {
    var isEnabled = false
    var scheme = "http"
    var host = "127.0.0.1"
    var port = "7890"
    var username = ""
    var bypassHosts = "localhost, 127.0.0.1, ::1, *.local"

    var endpoint: String {
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let authority = hostname.contains(":") && !hostname.hasPrefix("[") ? "[\(hostname)]" : hostname
        return "\(scheme)://\(authority):\(port.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func validationError(listenPort: Int) -> String? {
        guard isEnabled else { return nil }
        guard ["http", "https"].contains(scheme) else {
            return String(localized: "Choose an HTTP or HTTPS upstream proxy.", bundle: AppLocalization.bundle)
        }
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValidAddress = !hostname.contains(":")
            || IPv6Address(hostname.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) != nil
        guard !hostname.isEmpty,
              isValidAddress,
              !hostname.contains(where: { $0.isWhitespace || "/@?#\\".contains($0) }),
              let url = URLComponents(string: endpoint), url.host != nil,
              url.user == nil, url.password == nil else {
            return String(
                localized: "Enter a server hostname or IP address without a protocol or path.",
                bundle: AppLocalization.bundle
            )
        }
        guard let number = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(number) else {
            return String(localized: "Upstream port must be between 1 and 65535.", bundle: AppLocalization.bundle)
        }
        let loopback = hostname.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let isLoopback = ["localhost", "::1", "::", "0.0.0.0", "::ffff:127.0.0.1"].contains(loopback)
            || loopback.hasPrefix("127.")
        if number == listenPort && isLoopback {
            return String(
                localized: "The upstream proxy must not point to FRTMProxy's own listening port.",
                bundle: AppLocalization.bundle
            )
        }
        if username.contains(":") || username.contains(where: { $0.isNewline }) {
            return String(
                localized: "The upstream username cannot contain a colon or a newline.",
                bundle: AppLocalization.bundle
            )
        }
        return nil
    }

    func environment(password: String) throws -> [String: String] {
        guard isEnabled else { return [:] }
        let payload: [String: String] = [
            "bypass": bypassHosts,
            "auth": username.isEmpty ? "" : "\(username):\(password)"
        ]
        let data = try JSONEncoder().encode(payload)
        return ["FRTMPROXY_UPSTREAM": String(bytes: data, encoding: .utf8) ?? "{}"]
    }
}
