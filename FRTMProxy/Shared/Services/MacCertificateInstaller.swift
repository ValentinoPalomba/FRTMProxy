import Foundation

struct MacCertificateInstaller {
    enum Target {
        case loginKeychain
        case systemKeychain
    }

    enum InstallerError: LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let reason):
                return "Unable to trust the mitmproxy CA on macOS: \(reason)"
            }
        }
    }

    func install(target: Target = .loginKeychain) throws -> String {
        let pem = try MitmproxyCertificateLoader().pemURL()
        var arguments = ["add-trusted-cert", "-r", "trustRoot", "-p", "ssl", "-p", "basic"]
        if target == .systemKeychain {
            arguments.insert("-d", at: 1)
        }
        arguments += ["-k", keychainPath(for: target), pem.path]

        let result = ShellCommand.run("/usr/bin/security", arguments)
        guard result.succeeded else {
            throw InstallerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }

        switch target {
        case .loginKeychain:
            return "mitmproxy CA trusted in your login keychain. Traffic from this Mac's proxy-aware apps will now validate."
        case .systemKeychain:
            return "mitmproxy CA trusted in the System keychain (all users)."
        }
    }

    func isInstalled() -> Bool {
        let result = ShellCommand.run(
            "/usr/bin/security",
            ["find-certificate", "-c", "mitmproxy", keychainPath(for: .loginKeychain)]
        )
        return result.succeeded && !result.output.isEmpty
    }

    func remove(target: Target = .loginKeychain) throws {
        let result = ShellCommand.run(
            "/usr/bin/security",
            ["delete-certificate", "-c", "mitmproxy", keychainPath(for: target)]
        )
        guard result.succeeded else {
            throw InstallerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
    }

    private func keychainPath(for target: Target) -> String {
        switch target {
        case .systemKeychain:
            return "/Library/Keychains/System.keychain"
        case .loginKeychain:
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Keychains/login.keychain-db").path
        }
    }
}
