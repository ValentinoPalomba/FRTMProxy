import Foundation
import CryptoKit

/// Installs the ProxyCore Root CA into the user's Keychain (login keychain) and marks it as trusted.
///
/// Note: macOS will prompt the user to authorize changing trust settings. This does **not** require sudo,
/// but it cannot be fully silent.
struct MacCertificateInstaller {
    struct TrustStatus: Sendable {
        var sha1Hex: String
        var isTrusted: Bool
    }

    enum InstallerError: LocalizedError {
        case securityCommandFailed(String)
        case unableToResolveUserKeychain
        case trustVerificationFailed
        case authorizationCanceled

        var errorDescription: String? {
            switch self {
            case .securityCommandFailed(let reason):
                return "macOS certificate installation failed: \(reason)"
            case .unableToResolveUserKeychain:
                return "Unable to locate the default user keychain."
            case .trustVerificationFailed:
                return "Certificate was added, but trust settings weren't applied. Try again and accept the macOS prompt."
            case .authorizationCanceled:
                return "Authorization was canceled. macOS needs your confirmation to trust the certificate."
            }
        }
    }

    func trustStatus() async throws -> TrustStatus {
        let certificateDER = try await ProxyCoreCertificateLoader().loadRootCADER()
        let sha1 = Self.sha1Hex(certificateDER)
        let trusted = try isTrustedCertificate(sha1Hex: sha1)
        return TrustStatus(sha1Hex: sha1, isTrusted: trusted)
    }

    /// Installs the current ProxyCore Root CA as a trusted root for SSL (user trust domain).
    func installTrustedRootCA() async throws -> String {
        let statusBefore = try await trustStatus()
        if statusBefore.isTrusted {
            return "ProxyCore CA is already trusted on this Mac.\nSHA1: \(statusBefore.sha1Hex)"
        }

        let certificateDER = try await ProxyCoreCertificateLoader().loadRootCADER()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("frtmproxy-macos-ca-\(UUID().uuidString).cer")
        try certificateDER.write(to: temporaryURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let keychainPath = try resolveDefaultUserKeychainPath()

        let result = try runCommand(
            executable: "/usr/bin/security",
            arguments: [
                "add-trusted-cert",
                "-r", "trustRoot",
                "-p", "ssl",
                "-k", keychainPath,
                temporaryURL.path
            ]
        )

        let combinedOutput = (result.output + "\n" + result.error).lowercased()
        if combinedOutput.contains("authorization was canceled") {
            throw InstallerError.authorizationCanceled
        }

        guard result.status == 0 else {
            let reason = [result.error, result.output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw InstallerError.securityCommandFailed(reason.isEmpty ? "security returned status \(result.status)" : reason)
        }

        let statusAfter = try await trustStatus()
        guard statusAfter.isTrusted else {
            throw InstallerError.trustVerificationFailed
        }

        return """
        Installed and trusted “ProxyCore CA” in your login keychain.
        SHA1: \(statusAfter.sha1Hex)
        If HTTPS still fails, restart the target app/browser.
        """
    }

    private func resolveDefaultUserKeychainPath() throws -> String {
        // Example output:
        //   "/Users/<user>/Library/Keychains/login.keychain-db"
        let result = try runCommand(
            executable: "/usr/bin/security",
            arguments: ["default-keychain", "-d", "user"]
        )
        guard result.status == 0 else {
            throw InstallerError.unableToResolveUserKeychain
        }

        let line = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        if !line.isEmpty {
            return line
        }

        // Fallback to the usual login keychain location.
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains/login.keychain-db")
            .path
        return fallback
    }

    private func isTrustedCertificate(sha1Hex: String) throws -> Bool {
        // Trust settings keys are stored as uppercase hex SHA-1.
        let expected = sha1Hex.uppercased()

        let userKeys = try trustListKeys(extraArgs: [])
        if userKeys.contains(expected) { return true }

        // Best-effort: some environments may write trust settings in other domains.
        let adminKeys = try trustListKeys(extraArgs: ["-d"])
        if adminKeys.contains(expected) { return true }

        let systemKeys = try trustListKeys(extraArgs: ["-s"])
        if systemKeys.contains(expected) { return true }

        return false
    }

    private func trustListKeys(extraArgs: [String]) throws -> Set<String> {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("frtmproxy-trust-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        var args = ["trust-settings-export"]
        args.append(contentsOf: extraArgs)
        args.append(temporaryURL.path)

        let result = try runCommand(executable: "/usr/bin/security", arguments: args)
        guard result.status == 0 else {
            // No trust settings in this domain (or unavailable); treat as empty.
            return []
        }

        let data = try Data(contentsOf: temporaryURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard
            let dict = plist as? [String: Any],
            let trustList = dict["trustList"] as? [String: Any]
        else {
            return []
        }
        return Set(trustList.keys.map { $0.uppercased() })
    }

    private static func sha1Hex(_ data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
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
            throw InstallerError.securityCommandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (process.terminationStatus, output, errorText)
    }
}
