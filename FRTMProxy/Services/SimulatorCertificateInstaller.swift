import Foundation

struct SimulatorCertificateInstaller {
    struct BootedSimulator: Sendable {
        var udid: String
        var name: String
    }

    enum InstallerError: LocalizedError {
        case simctlFailed(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .simctlFailed(let reason):
                return """
                simctl ha restituito un errore: \(reason.isEmpty ? "esegui almeno un simulatore prima di procedere" : reason)
                """
            case .commandFailed(let reason):
                return "Impossibile eseguire un comando richiesto: \(reason)"
            }
        }
    }

    func installCertificateOnBootedSimulators() throws -> String {
        let booted = try bootedSimulators()
        guard !booted.isEmpty else {
            throw InstallerError.simctlFailed("nessun simulatore avviato (booted)")
        }

        let certificateDER = try MitmproxyCertificateLoader().loadRootCADER()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("frtmproxy-sim-ca-\(UUID().uuidString).cer")
        try certificateDER.write(to: temporaryURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        var installedOn: [String] = []
        var alreadyOn: [String] = []
        var failures: [String] = []
        var verifiedOn: [String] = []

        for device in booted {
            let result = try runCommand(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "keychain", device.udid, "add-root-cert", temporaryURL.path]
            )

            let combined = (result.error + "\n" + result.output).lowercased()
            if result.status != 0 {
                failures.append("\(device.name) (\(device.udid))")
                continue
            }
            if combined.contains("already") && combined.contains("exists") {
                alreadyOn.append(device.name)
            } else {
                installedOn.append(device.name)
            }

            if verifyMitmproxyCertPresent(udid: device.udid) == true {
                verifiedOn.append(device.name)
            }
        }

        var parts: [String] = []
        if !installedOn.isEmpty {
            parts.append("Installato su: " + installedOn.joined(separator: ", "))
        }
        if !alreadyOn.isEmpty {
            parts.append("Già presente su: " + alreadyOn.joined(separator: ", "))
        }
        if !verifiedOn.isEmpty {
            parts.append("Verificato in keychain: " + verifiedOn.joined(separator: ", "))
        } else {
            parts.append("Nota: la verifica automatica non è disponibile su questa macchina; se non lo vedi in UI, riavvia il simulatore.")
        }
        if !failures.isEmpty {
            parts.append("Fallito su: " + failures.joined(separator: ", "))
        }

        return parts.joined(separator: "\n")
    }

    func bootedSimulators() throws -> [BootedSimulator] {
        let result = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "booted", "-j"]
        )
        guard result.status == 0 else {
            throw InstallerError.simctlFailed(result.error.isEmpty ? result.output : result.error)
        }

        guard let data = result.output.data(using: .utf8) else { return [] }
        let decoded = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        let devices = decoded.devices.values.flatMap { $0 }.map { BootedSimulator(udid: $0.udid, name: $0.name) }
        let unique = Dictionary(grouping: devices, by: \.udid).compactMap { $0.value.first }
        return unique.sorted(by: { $0.name < $1.name })
    }

    private struct SimctlDeviceList: Decodable {
        var devices: [String: [SimctlDevice]]
    }

    private struct SimctlDevice: Decodable {
        var name: String
        var udid: String
    }

    private func verifyMitmproxyCertPresent(udid: String) -> Bool? {
        do {
            let result = try runCommand(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "spawn", udid, "security", "find-certificate", "-a", "-c", "mitmproxy"]
            )
            if result.status != 0 {
                return nil
            }
            return !trimmed(result.output).isEmpty
        } catch {
            return nil
        }
    }

    private func runCommand(executable: String, arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw InstallerError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (process.terminationStatus, output, trimmed(errorText))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
