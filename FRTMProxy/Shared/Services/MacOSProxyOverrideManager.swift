import Foundation

enum MacOSProxyOverrideError: LocalizedError {
    case commandFailed(command: String, output: String)
    case parseFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, output):
            return "macOS proxy override failed: \(command)\n\(output)"
        case let .parseFailed(command, output):
            return "macOS proxy override failed: unable to parse output for \(command)\n\(output)"
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
    private let networksetupPath = "/usr/sbin/networksetup"
    private let overrideHosts: Set<String> = ["localhost", "127.0.0.1"]

    func enableProxy(host: String, port: Int) throws {
        let services = try listEnabledNetworkServices()
        var snapshot = loadSnapshot() ?? MacOSProxySnapshot(services: [:])
        var snapshotUpdated = false

        // 1) Cattura lo stato originale di TUTTI i servizi prima di modificare
        //    qualunque cosa, così lo snapshot riflette il sistema pre-override.
        for service in services where snapshot.services[service] == nil {
            snapshot.services[service] = try readServiceSettings(service)
            snapshotUpdated = true
        }

        // 2) Persisti lo snapshot PRIMA di applicare: un crash a metà apply
        //    non lascia il sistema con un proxy non più ripristinabile.
        if snapshotUpdated {
            persistSnapshot(snapshot)
        }

        // 3) Applica l'override su ogni servizio.
        for service in services {
            try applyProxySettings(
                .init(enabled: true, host: host, port: port),
                service: service,
                secure: false
            )
            try applyProxySettings(
                .init(enabled: true, host: host, port: port),
                service: service,
                secure: true
            )
        }
    }

    func disableProxy() throws {
        let services = Set(try listEnabledNetworkServices())

        if let snapshot = loadSnapshot() {
            for (service, serviceSnapshot) in snapshot.services where services.contains(service) {
                try applyProxySettings(serviceSnapshot.http, service: service, secure: false)
                try applyProxySettings(serviceSnapshot.https, service: service, secure: true)
            }
            clearSnapshot()
            return
        }

        var didChange = false
        for service in services {
            let current = try readServiceSettings(service)
            if shouldDisableOverride(current.http) {
                try setProxyState(service: service, enabled: false, secure: false)
                didChange = true
            }
            if shouldDisableOverride(current.https) {
                try setProxyState(service: service, enabled: false, secure: true)
                didChange = true
            }
        }

        if didChange {
            clearSnapshot()
        }
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

    private func applyProxySettings(_ settings: MacOSProxySnapshot.ProxySettings, service: String, secure: Bool) throws {
        if settings.enabled {
            guard let host = settings.host, let port = settings.port else {
                try setProxyState(service: service, enabled: false, secure: secure)
                return
            }
            try setProxyHostPort(service: service, host: host, port: port, secure: secure)
            try setProxyState(service: service, enabled: true, secure: secure)
        } else {
            try setProxyState(service: service, enabled: false, secure: secure)
        }
    }

    private func setProxyHostPort(service: String, host: String, port: Int, secure: Bool) throws {
        let command = secure ? "-setsecurewebproxy" : "-setwebproxy"
        _ = try runNetworksetup(arguments: [command, service, host, "\(port)"])
    }

    private func setProxyState(service: String, enabled: Bool, secure: Bool) throws {
        let command = secure ? "-setsecurewebproxystate" : "-setwebproxystate"
        _ = try runNetworksetup(arguments: [command, service, enabled ? "on" : "off"])
    }

    private func shouldDisableOverride(_ settings: MacOSProxySnapshot.ProxySettings) -> Bool {
        guard settings.enabled, let host = settings.host?.lowercased() else {
            return false
        }
        return overrideHosts.contains(host)
    }

    private func runNetworksetup(arguments: [String]) throws -> String {
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
