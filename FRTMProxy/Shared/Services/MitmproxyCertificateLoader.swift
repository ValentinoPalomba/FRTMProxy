import Foundation

struct MitmproxyCertificateLoader {
    enum LoaderError: LocalizedError {
        case certificateMissing(basePath: String)
        case conversionFailed(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .certificateMissing(let path):
                return """
                mitmproxy CA certificate not found in \(path). \
                Start the proxy once (even just opening mitm.it) to generate it.
                """
            case .conversionFailed(let reason):
                return "Unable to convert the PEM certificate to DER: \(reason)"
            case .commandFailed(let reason):
                return "Unable to execute a required command: \(reason)"
            }
        }
    }

    func loadRootCADER() throws -> Data {
        let resolved = try resolvedCertificateURL()
        defer { resolved.cleanup?() }
        return try Data(contentsOf: resolved.url)
    }

    private func resolvedCertificateURL() throws -> (url: URL, cleanup: (() -> Void)?) {
        let fileManager = FileManager.default
        let baseURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".mitmproxy")

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: baseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LoaderError.certificateMissing(basePath: baseURL.path)
        }

        let cerURL = baseURL.appendingPathComponent("mitmproxy-ca-cert.cer")
        if fileManager.fileExists(atPath: cerURL.path) {
            return (cerURL, nil)
        }

        let pemURL = baseURL.appendingPathComponent("mitmproxy-ca-cert.pem")
        guard fileManager.fileExists(atPath: pemURL.path) else {
            throw LoaderError.certificateMissing(basePath: baseURL.path)
        }

        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("mitmproxy-ca-\(UUID().uuidString).cer")
        do {
            try convertPEM(at: pemURL, toDER: temporaryURL)
        } catch {
            throw LoaderError.conversionFailed(error.localizedDescription)
        }

        return (temporaryURL, {
            try? fileManager.removeItem(at: temporaryURL)
        })
    }

    private func convertPEM(at source: URL, toDER destination: URL) throws {
        let result = try runCommand(
            executable: "/usr/bin/openssl",
            arguments: [
                "x509",
                "-in", source.path,
                "-out", destination.path,
                "-outform", "der"
            ]
        )

        guard result.status == 0 else {
            throw LoaderError.commandFailed(result.error.isEmpty ? result.output : result.error)
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
            throw LoaderError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, trimmed(output), trimmed(errorText))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
