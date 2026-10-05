import Foundation
import Darwin

enum MacOSProxyOverrideError: LocalizedError {
    case ownershipChanged(String)
    case commandFailed(command: String, output: String)
    case parseFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .ownershipChanged(let service):
            return "Proxy settings changed outside FRTMProxy for \(service); they were preserved."
        case let .commandFailed(command, output):
            return "macOS proxy override failed: \(command)\n\(output)"
        case let .parseFailed(command, output):
            return "macOS proxy override failed: unable to parse output for \(command)\n\(output)"
        }
    }
}

struct MacOSProxySnapshot: Codable {
    struct ProxySettings: Codable, Equatable {
        let enabled: Bool
        let host: String?
        let port: Int?
    }

    struct ServiceSettings: Codable {
        let http: ProxySettings
        let https: ProxySettings
    }

    var services: [String: ServiceSettings]
    var override: ProxySettings?
    var ownerProcessID: Int32?
}

actor MacOSProxyOverrideManager {
    static let shared = MacOSProxyOverrideManager()

    private let snapshotKey = "settings.macosProxyOverride.snapshot"
    private let defaults: UserDefaults
    private let journalURL: URL
    private let commandRunner: (@Sendable ([String]) throws -> String)?
    private let networksetupPath = "/usr/sbin/networksetup"

    init(defaults: UserDefaults = .standard, journalURL: URL = URL.applicationSupportDirectory.appending(path: "FRTMProxy/Recovery/proxy.json"), commandRunner: (@Sendable ([String]) throws -> String)? = nil) {
        self.defaults = defaults
        self.journalURL = journalURL
        self.commandRunner = commandRunner
    }


    func enableProxy(host: String, port: Int) throws {
        let services = try listEnabledNetworkServices()
        var snapshot = try loadSnapshot() ?? MacOSProxySnapshot(services: [:])
        if let owner = snapshot.ownerProcessID,
           owner != ProcessInfo.processInfo.processIdentifier, kill(owner, 0) == 0 {
            throw MacOSProxyOverrideError.ownershipChanged("another running FRTMProxy instance")
        }
        let target = MacOSProxySnapshot.ProxySettings(enabled: true, host: host, port: port)
        for service in services {
            let current = try readServiceSettings(service)
            if snapshot.services[service] == nil {
                snapshot.services[service] = current
            } else if let owned = snapshot.override {
                guard current.http == owned && current.https == owned else {
                    throw MacOSProxyOverrideError.ownershipChanged(service)
                }
            } else {
                // A legacy snapshot has no ownership evidence. Never guess from a loopback host.
                throw MacOSProxyOverrideError.ownershipChanged(service)
            }
        }
        if let owned = snapshot.override, owned != target {
            // Finish the old transaction before recording a different endpoint.
            // A failed port change can then roll back using a single ownership value.
            try disableProxy()
            guard try loadSnapshot() == nil else {
                throw MacOSProxyOverrideError.ownershipChanged("unavailable network services")
            }
            try enableProxy(host: host, port: port)
            return
        }
        // Record intent before the first mutation so a partial failure can be recovered.
        snapshot.override = target
        snapshot.ownerProcessID = ProcessInfo.processInfo.processIdentifier
        try persistSnapshot(snapshot)
        do {
            for service in services {
                try applyProxySettings(target, service: service, secure: false)
                try applyProxySettings(target, service: service, secure: true)
            }
        } catch {
            try? disableProxy()
            throw error
        }
    }

    func disableProxy(expectedOwnerPID: Int32? = nil) throws {
        guard var snapshot = try loadSnapshot(), let owned = snapshot.override else { return }
        if let expectedOwnerPID, snapshot.ownerProcessID != expectedOwnerPID { return }
        if expectedOwnerPID == nil, let owner = snapshot.ownerProcessID,
           owner != ProcessInfo.processInfo.processIdentifier, kill(owner, 0) == 0 {
            return
        }
        let available = Set(try listEnabledNetworkServices())
        var firstError: Error?
        for (service, previous) in snapshot.services where available.contains(service) {
            do {
                let current = try readServiceSettings(service)
                // Restore each protocol independently, preserving user changes and partial activation.
                if Self.owns(current.http, override: owned) {
                    try applyProxySettings(previous.http, service: service, secure: false)
                }
                if Self.owns(current.https, override: owned) {
                    try applyProxySettings(previous.https, service: service, secure: true)
                }
                snapshot.services.removeValue(forKey: service)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if snapshot.services.isEmpty { try clearSnapshot() } else { try persistSnapshot(snapshot) }
        if let firstError { throw firstError }
    }

    static func owns(_ current: MacOSProxySnapshot.ProxySettings, override owned: MacOSProxySnapshot.ProxySettings) -> Bool {
        // Disabling or changing the endpoint externally relinquishes ownership.
        current == owned
    }

    private func listEnabledNetworkServices() throws -> [String] {
        let output = try runNetworksetup(arguments: ["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("An asterisk") &&
                !line.hasPrefix("*")
            }
    }

    private func readServiceSettings(_ service: String) throws -> MacOSProxySnapshot.ServiceSettings {
        let webOutput = try runNetworksetup(arguments: ["-getwebproxy", service])
        let secureWebOutput = try runNetworksetup(arguments: ["-getsecurewebproxy", service])
        return .init(
            http: try parseProxySettings(output: webOutput, command: "-getwebproxy"),
            https: try parseProxySettings(output: secureWebOutput, command: "-getsecurewebproxy")
        )
    }

    private func parseProxySettings(output: String, command: String) throws -> MacOSProxySnapshot.ProxySettings {
        var enabled = false
        var host: String?
        var port: Int?
        var foundEnabledKey = false

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "enabled":
                foundEnabledKey = true
                enabled = value.lowercased().hasPrefix("yes")
            case "server":
                host = value.isEmpty ? nil : value
            case "port":
                port = Int(value)
            default:
                break
            }
        }

        guard foundEnabledKey else {
            throw MacOSProxyOverrideError.parseFailed(command: command, output: output)
        }

        return .init(enabled: enabled, host: host, port: port)
    }

    private func applyProxySettings(
        _ settings: MacOSProxySnapshot.ProxySettings,
        service: String,
        secure: Bool
    ) throws {
        if let host = settings.host, let port = settings.port {
            try setProxyHostPort(service: service, host: host, port: port, secure: secure)
        }
        try setProxyState(service: service, enabled: settings.enabled, secure: secure)
    }

    private func setProxyHostPort(service: String, host: String, port: Int, secure: Bool) throws {
        let command = secure ? "-setsecurewebproxy" : "-setwebproxy"
        _ = try runNetworksetup(arguments: [command, service, host, "\(port)"])
    }

    private func setProxyState(service: String, enabled: Bool, secure: Bool) throws {
        let command = secure ? "-setsecurewebproxystate" : "-setwebproxystate"
        _ = try runNetworksetup(arguments: [command, service, enabled ? "on" : "off"])
    }

    private func runNetworksetup(arguments: [String]) throws -> String {
        if let commandRunner { return try commandRunner(arguments) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: networksetupPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = [stdout, stderr]
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let commandString = ([networksetupPath] + arguments).joined(separator: " ")
            throw MacOSProxyOverrideError.commandFailed(command: commandString, output: combined)
        }

        return stdout
    }

    private func loadSnapshot() throws -> MacOSProxySnapshot? {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            return try JSONDecoder().decode(MacOSProxySnapshot.self, from: Data(contentsOf: journalURL))
        }
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try JSONDecoder().decode(MacOSProxySnapshot.self, from: data)
    }

    private func persistSnapshot(_ snapshot: MacOSProxySnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        defaults.set(data, forKey: snapshotKey)
    }

    private func clearSnapshot() throws {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            try FileManager.default.removeItem(at: journalURL)
        }
        defaults.removeObject(forKey: snapshotKey)
    }
}
