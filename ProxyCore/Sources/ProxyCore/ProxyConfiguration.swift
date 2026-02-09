import Foundation

public struct ProxyConfiguration: Sendable {
    public enum UpstreamTLSVerification: Sendable {
        case trustAll
        case systemRoots
    }

    public struct ExternalProxy: Sendable {
        public var host: String
        public var port: Int
        public var username: String?
        public var password: String?
        public var capturePacket: Bool

        public init(
            host: String,
            port: Int,
            username: String? = nil,
            password: String? = nil,
            capturePacket: Bool = true
        ) {
            self.host = host
            self.port = port
            self.username = username
            self.password = password
            self.capturePacket = capturePacket
        }

        /// Returns the value for the `Proxy-Authorization` header (Basic), if credentials are present.
        public func basicAuthHeaderValue() -> String? {
            guard
                let username, !username.isEmpty,
                let password
            else {
                return nil
            }
            let token = "\(username):\(password)"
            let encoded = Data(token.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }

    public struct RemoteForward: Sendable {
        public var enabled: Bool
        public var host: String
        public var port: Int

        public init(enabled: Bool, host: String, port: Int) {
            self.enabled = enabled
            self.host = host
            self.port = port
        }
    }

    public struct HostFilter: Sendable {
        public var whitelistEnabled: Bool
        public var whitelistPatterns: [String]

        public var blacklistEnabled: Bool
        public var blacklistPatterns: [String]

        public init(
            whitelistEnabled: Bool = false,
            whitelistPatterns: [String] = [],
            blacklistEnabled: Bool = true,
            blacklistPatterns: [String] = ["(.*\\.)?apple\\.com", "(.*\\.)?icloud\\.com"]
        ) {
            self.whitelistEnabled = whitelistEnabled
            self.whitelistPatterns = whitelistPatterns
            self.blacklistEnabled = blacklistEnabled
            self.blacklistPatterns = blacklistPatterns
        }
    }

    public struct Paths: Sendable {
        public var baseDirectory: URL

        public init(baseDirectory: URL) {
            self.baseDirectory = baseDirectory
        }

        public static func defaultPaths() throws -> Paths {
            let base = try FileManager.default
                .url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                .appending(path: "FRTMProxy", directoryHint: .isDirectory)
                .appending(path: "ProxyCore", directoryHint: .isDirectory)
            return Paths(baseDirectory: base)
        }
    }

    public var listenHost: String
    public var listenPort: Int

    public var enableMITM: Bool
    public var enableHTTP2: Bool

    public var maxCapturedBodyBytes: Int

    public var upstreamTLSVerification: UpstreamTLSVerification

    public var externalProxy: ExternalProxy?
    public var remoteForward: RemoteForward?

    public var socks5InboundEnabled: Bool

    public var hostFilter: HostFilter

    public var paths: Paths
    
    /// Closure to check if a domain is approved for MITM.
    /// If returns nil/false, domain will be bypassed (no MITM).
    /// If returns true, domain will be intercepted.
    public var isDomainApprovedForMITM: (@Sendable (String) -> Bool)?
    
    /// Closure called when a new domain is discovered.
    /// Useful for marking domains as "pending" in the approval store.
    public var onNewDomainDiscovered: (@Sendable (String) -> Void)?

    public init(
        listenHost: String = "0.0.0.0",
        listenPort: Int = 9099,
        enableMITM: Bool = true,
        enableHTTP2: Bool = true,
        maxCapturedBodyBytes: Int = 4 * 1024 * 1024,
        upstreamTLSVerification: UpstreamTLSVerification = .trustAll,
        externalProxy: ExternalProxy? = nil,
        remoteForward: RemoteForward? = nil,
        socks5InboundEnabled: Bool = true,
        hostFilter: HostFilter = HostFilter(),
        paths: Paths? = nil,
        isDomainApprovedForMITM: (@Sendable (String) -> Bool)? = nil,
        onNewDomainDiscovered: (@Sendable (String) -> Void)? = nil
    ) {
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.enableMITM = enableMITM
        self.enableHTTP2 = enableHTTP2
        self.maxCapturedBodyBytes = maxCapturedBodyBytes
        self.upstreamTLSVerification = upstreamTLSVerification
        self.externalProxy = externalProxy
        self.remoteForward = remoteForward
        self.socks5InboundEnabled = socks5InboundEnabled
        self.hostFilter = hostFilter
        self.paths = paths ?? (try? Paths.defaultPaths()) ?? Paths(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("FRTMProxy-fallback"))
        self.isDomainApprovedForMITM = isDomainApprovedForMITM
        self.onNewDomainDiscovered = onNewDomainDiscovered
    }
}
