import Foundation

enum MacOSProxyOverrideError: LocalizedError {
    case commandFailed(String)
    case invalidServiceList
    case snapshotEncodingFailed
    case snapshotDecodingFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "networksetup failed: \(message)"
        case .invalidServiceList:
            return "Unable to retrieve network services."
        case .snapshotEncodingFailed:
            return "Failed to encode proxy snapshot."
        case .snapshotDecodingFailed:
            return "Failed to decode proxy snapshot."
        }
    }
}

struct MacOSProxySnapshot: Codable {
    struct ProxySettings: Codable {
        let enabled: Bool
        let host: String?
        let port: Int?
    }

    struct ServiceSettings: Codable {
        let http: ProxySettings
        let https: ProxySettings
    }

    var services: [String: ServiceSettings]
}

actor MacOSProxyOverrideManager {

    static let shared = MacOSProxyOverrideManager()

    private let snapshotKey = "settings.macosProxyOverride.snapshot"
    private let defaults = UserDefaults.standard

    // MARK: - Public

    func enableProxy(host: String, port: Int) throws {
        let services = try listNetworkServices()
        var snapshot = loadSnapshot() ?? MacOSProxySnapshot(services: [:])

        for service in services {
            if snapshot.services[service] == nil {
                snapshot.services[service] = try captureServiceSnapshot(service)
            }

            try runNetworkSetup([
                "-setwebproxy", service, host, "\(port)"
            ])
            try runNetworkSetup([
                "-setsecurewebproxy", service, host, "\(port)"
            ])
            try runNetworkSetup([
                "-setwebproxystate", service, "on"
            ])
            try runNetworkSetup([
                "-setsecurewebproxystate", service, "on"
            ])
        }

        persistSnapshot(snapshot)
    }

    func disableProxy() throws {
        guard let snapshot = loadSnapshot() else {
            try disableProxyWithoutSnapshot()
            return
        }

        for (service, settings) in snapshot.services {
            try restore(service: service, settings: settings)
        }

        clearSnapshot()
    }

    // MARK: - Snapshot Capture

    private func captureServiceSnapshot(_ service: String) throws -> MacOSProxySnapshot.ServiceSettings {
        let http = try readProxy(service: service, secure: false)
        let https = try readProxy(service: service, secure: true)
        return .init(http: http, https: https)
    }

    private func readProxy(service: String, secure: Bool) throws -> MacOSProxySnapshot.ProxySettings {
        let flag = secure ? "-getsecurewebproxy" : "-getwebproxy"
        let output = try runNetworkSetup([flag, service])

        let enabled = output.contains("Enabled: Yes")

        let host = parseValue(from: output, key: "Server")
        let portString = parseValue(from: output, key: "Port")
        let port = portString.flatMap { Int($0) }

        return .init(enabled: enabled, host: host, port: port)
    }

    // MARK: - Restore

    private func restore(service: String, settings: MacOSProxySnapshot.ServiceSettings) throws {
        try restoreProxy(service: service, settings: settings.http, secure: false)
        try restoreProxy(service: service, settings: settings.https, secure: true)
    }

    private func restoreProxy(service: String,
                              settings: MacOSProxySnapshot.ProxySettings,
                              secure: Bool) throws {

        let setFlag = secure ? "-setsecurewebproxy" : "-setwebproxy"
        let stateFlag = secure ? "-setsecurewebproxystate" : "-setwebproxystate"

        if let host = settings.host, let port = settings.port {
            try runNetworkSetup([setFlag, service, host, "\(port)"])
        }

        try runNetworkSetup([
            stateFlag, service, settings.enabled ? "on" : "off"
        ])
    }

    private func disableProxyWithoutSnapshot() throws {
        let services = try listNetworkServices()

        for service in services {
            try runNetworkSetup(["-setwebproxystate", service, "off"])
            try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        }
    }

    // MARK: - Helpers

    private func listNetworkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        let lines = output
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.contains("(*)") } // ignore disabled
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw MacOSProxyOverrideError.invalidServiceList
        }

        return lines
    }

    @discardableResult
    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw MacOSProxyOverrideError.commandFailed(output)
        }

        return output
    }

    private func parseValue(from output: String, key: String) -> String? {
        output
            .split(separator: "\n")
            .first(where: { $0.contains("\(key):") })?
            .split(separator: ":")
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Persistence

    private func loadSnapshot() -> MacOSProxySnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(MacOSProxySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func persistSnapshot(_ snapshot: MacOSProxySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private func clearSnapshot() {
        defaults.removeObject(forKey: snapshotKey)
    }
}
