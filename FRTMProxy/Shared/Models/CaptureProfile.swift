import Foundation
import Darwin

struct CaptureProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var members: [CaptureProfileMember] = []
    var legacyFilter: FlowFilter?

    func matches(_ flow: MitmFlow) -> Bool {
        members.contains { $0.matches(flow) } || (legacyFilter.map { !$0.apply(to: [flow]).isEmpty } ?? false)
    }

    /// Normalize saved membership once per profile change, rather than for every row.
    struct MembershipIndex {
        private var requests = Set<CaptureProfileMember>()
        private var hosts = Set<String>()
        private var apps = Set<String>()

        init(_ members: [CaptureProfileMember]) {
            for member in members.compactMap(\.normalized) {
                switch member {
                case .request: requests.insert(member)
                case let .host(host): hosts.insert(host)
                case let .app(app): apps.insert(app)
                }
            }
        }

        func matches(_ flow: MitmFlow) -> Bool {
            if !apps.isEmpty, let app = flow.clientApp,
               apps.contains(FlowClientApp.normalizedID(app.id)) { return true }
            if !hosts.isEmpty, let url = flow.request?.url,
               let rawHost = URLComponents(string: url)?.host,
               case let .host(host)? = CaptureProfileMember.host(rawHost).normalized,
               hosts.contains(host) { return true }
            if !requests.isEmpty, let request = CaptureProfileMember.request(for: flow) {
                return requests.contains(request)
            }
            return false
        }
    }

}

enum CaptureProfileMember: Codable, Hashable, Sendable {
    case request(method: String, url: String)
    case host(String)
    case app(String)

    var displayName: String {
        switch self {
        case let .request(method, url): return "\(method) \(url)"
        case let .host(host): return host
        case let .app(app): return app
        }
    }

    static func request(for flow: MitmFlow) -> Self? {
        guard let request = flow.request else { return nil }
        return Self.request(method: request.method, url: request.url).normalized
    }

    var normalized: Self? {
        switch self {
        case let .host(value):
            guard let host = Self.normalizedHost(value) else { return nil }
            return .host(host)
        case let .app(value):
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            let app = FlowClientApp.normalizedID(value)
            guard !app.isEmpty, !app.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            }) else { return nil }
            return .app(app)
        case let .request(method, url):
            let method = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !method.isEmpty, method.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
                  var parts = URLComponents(string: url),
                  let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = parts.host, !host.isEmpty else { return nil }
            parts.scheme = scheme
            parts.host = host.lowercased()
            parts.user = nil
            parts.password = nil
            parts.query = nil
            parts.fragment = nil
            if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
            if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
            guard let url = parts.string else { return nil }
            return .request(method: method, url: url)
        }
    }

    private static func normalizedHost(_ value: String) -> String? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        var host = PinnedHost.normalized(value)
        guard !host.isEmpty, !host.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.contains(":") {
            var address = in6_addr()
            guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
            // Canonical spelling makes expanded and compressed IPv6 literals equivalent.
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        }
        guard !host.contains(where: { "/?#@\\%[]".contains($0) }) else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        guard let ascii = URL(string: "http://" + host)?.host?.lowercased(), ascii.utf8.count <= 253 else { return nil }
        let labels = ascii.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
        }) else { return nil }
        if labels.count > 1, labels.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }) {
            var address = in_addr()
            guard ascii.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
        }
        return ascii
    }

    func matches(_ flow: MitmFlow) -> Bool {
        guard let member = normalized else { return false }
        switch member {
        case .request: return Self.request(for: flow) == member
        case let .host(host):
            guard let url = flow.request?.url, let flowHost = URLComponents(string: url)?.host else { return false }
            return Self.normalizedHost(flowHost) == host
        case let .app(app): return flow.clientApp.map { FlowClientApp.normalizedID($0.id) == app } ?? false
        }
    }
}
