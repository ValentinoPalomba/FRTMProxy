import Foundation
import Security

enum CertificateManagerError: LocalizedError {
    case opensslFailed(String)
    case identityImportFailed(OSStatus)
    case certificateNotFound
    case privateKeyNotFound

    var errorDescription: String? {
        switch self {
        case .opensslFailed(let reason):
            return "OpenSSL command failed: \(reason)"
        case .identityImportFailed(let status):
            return "Failed to import SecIdentity: OSStatus \(status)"
        case .certificateNotFound:
            return "Certificate file not found"
        case .privateKeyNotFound:
            return "Private key file not found"
        }
    }
}

final class CertificateManager {
    static let shared = CertificateManager()

    private let fileManager = FileManager.default
    private let caName = "FRTMProxy-Root-CA"

    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("FRTMProxy", isDirectory: true)
        let certs = base.appendingPathComponent("Certificates", isDirectory: true)
        try? fileManager.createDirectory(at: certs, withIntermediateDirectories: true)
        return certs
    }

    private var caCertURL: URL { baseDirectory.appendingPathComponent("ca.crt") }
    private var caKeyURL: URL { baseDirectory.appendingPathComponent("ca.key") }

    private init() {}

    func ensureRootCA() throws {
        if fileManager.fileExists(atPath: caCertURL.path) && fileManager.fileExists(atPath: caKeyURL.path) {
            return
        }

        // Generate Root CA
        try runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", caKeyURL.path,
            "-out", caCertURL.path,
            "-days", "3650",
            "-nodes",
            "-subj", "/C=US/ST=CA/L=SanFrancisco/O=FRTMProxy/CN=\(caName)"
        ])
    }

    func caCertificateData() throws -> Data {
        try ensureRootCA()
        return try Data(contentsOf: caCertURL)
    }

    func caCertificateURL() -> URL {
        return caCertURL
    }

    func identity(for host: String) throws -> SecIdentity {
        try ensureRootCA()

        let hostDir = baseDirectory.appendingPathComponent("Hosts", isDirectory: true)
        try? fileManager.createDirectory(at: hostDir, withIntermediateDirectories: true)

        let hostCertURL = hostDir.appendingPathComponent("\(host).crt")
        let hostKeyURL = hostDir.appendingPathComponent("\(host).key")
        let p12URL = hostDir.appendingPathComponent("\(host).p12")

        // Use a fixed password for the P12 export/import
        let password = "proxy"

        if !fileManager.fileExists(atPath: hostCertURL.path) {
            // Generate leaf key and CSR
            try runOpenSSL([
                "req", "-newkey", "rsa:2048",
                "-nodes",
                "-keyout", hostKeyURL.path,
                "-out", hostDir.appendingPathComponent("\(host).csr").path,
                "-subj", "/CN=\(host)"
            ])

            // Sign leaf certificate
            try runOpenSSL([
                "x509", "-req",
                "-in", hostDir.appendingPathComponent("\(host).csr").path,
                "-CA", caCertURL.path,
                "-CAkey", caKeyURL.path,
                "-CAcreateserial",
                "-out", hostCertURL.path,
                "-days", "365"
            ])
        }

        // Create PKCS12
        try runOpenSSL([
            "pkcs12", "-export",
            "-out", p12URL.path,
            "-inkey", hostKeyURL.path,
            "-in", hostCertURL.path,
            "-passout", "pass:\(password)"
        ])

        let p12Data = try Data(contentsOf: p12URL)
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]

        var rawItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess, let items = rawItems as? [[String: Any]], let firstItem = items.first else {
            throw CertificateManagerError.identityImportFailed(status)
        }

        guard let identity = firstItem[kSecImportItemIdentity as String] as? SecIdentity else {
            throw CertificateManagerError.certificateNotFound
        }

        return identity
    }

    private func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CertificateManagerError.opensslFailed(errorString)
        }
    }
}
