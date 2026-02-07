import Foundation
import Crypto
import NIO
import NIOSSL
import SwiftASN1
import X509
import _CryptoExtras
#if canImport(Security)
import Security
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum CertificateAuthorityError: Error {
    case invalidBaseDirectory
    case failedToCreateDirectory(URL)
    case failedToReadFile(URL)
    case failedToWriteFile(URL)
    case invalidPEM
    case certificateGenerationFailed(String)
    case pkcs12Unsupported
    case pkcs12ImportFailed(String)
    case pkcs12ExportFailed(String)
}

public actor CertificateAuthority {
    public struct LeafConfig: Sendable {
        public var host: String
        public var alpnProtocols: [String]

        public init(host: String, alpnProtocols: [String]) {
            self.host = host
            self.alpnProtocols = alpnProtocols
        }
    }

    private struct CacheEntry {
        var createdAt: Date
        var sslContext: NIOSSLContext
    }

    private let baseDirectory: URL

    private let rootCertURL: URL
    private let rootKeyURL: URL

    private var rootCertificate: Certificate?
    private var rootPrivateKey: Certificate.PrivateKey?

    private var leafPrivateKey: Certificate.PrivateKey?

    private var leafContextCache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60 * 15

    public init(baseDirectory: URL) throws {
        self.baseDirectory = baseDirectory

        self.rootCertURL = baseDirectory.appending(path: "ca.crt", directoryHint: .notDirectory)
        self.rootKeyURL = baseDirectory.appending(path: "ca_key.pem", directoryHint: .notDirectory)

        try Self.ensureDirectoryExists(baseDirectory)
    }

    public func rootCertificatePEM() async throws -> String {
        try await ensureRootCA()
        guard let cert = rootCertificate else { throw CertificateAuthorityError.invalidPEM }
        return try cert.serializeAsPEM().pemString
    }

    public func rootCertificateDER() async throws -> Data {
        try await ensureRootCA()
        guard let cert = rootCertificate else { throw CertificateAuthorityError.invalidPEM }
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    public func generateNewRootCA(commonName: String = "ProxyCore CA") async throws {
        // Blow away persisted files and regenerate.
        try? FileManager.default.removeItem(at: rootCertURL)
        try? FileManager.default.removeItem(at: rootKeyURL)
        rootCertificate = nil
        rootPrivateKey = nil
        leafPrivateKey = nil
        leafContextCache.removeAll()
        try await ensureRootCA(customCommonName: commonName)
    }

    // MARK: - PKCS#12 (best-effort)

    public func exportRootCAPKCS12(password: String) async throws -> Data {
        try await ensureRootCA()
        guard let cert = rootCertificate, let key = rootPrivateKey else {
            throw CertificateAuthorityError.invalidPEM
        }

        #if canImport(Security)
        if let exported = try? Self.exportPKCS12WithSecurity(certificate: cert, privateKey: key, password: password) {
            return exported
        }
        #endif

        // Fallback: try using the system `openssl` if available.
        if let exported = try? await exportPKCS12WithOpenSSL(password: password) {
            return exported
        }

        throw CertificateAuthorityError.pkcs12ExportFailed("Unable to export PKCS#12")
    }

    public func importRootCAPKCS12(_ data: Data, password: String) async throws {
        #if canImport(Security)
        let imported = try Self.importPKCS12WithSecurity(data: data, password: password)

        // Best effort: try to persist as PEM (preferred format for our on-disk layout).
        if let keyPEM = try? imported.privateKey.serializeAsPEM().pemString {
            rootCertificate = imported.certificate
            rootPrivateKey = imported.privateKey
            leafPrivateKey = nil
            leafContextCache.removeAll()
            try persistRootCA(cert: imported.certificate, keyPEM: keyPEM)
            return
        }

        // Fallback: extract PEM via `openssl` (avoids SecKey export restrictions on some platforms/key types).
        if let opensslImported = try? await importPKCS12WithOpenSSL(data: data, password: password) {
            rootCertificate = opensslImported.certificate
            rootPrivateKey = opensslImported.privateKey
            leafPrivateKey = nil
            leafContextCache.removeAll()
            try persistRootCA(cert: opensslImported.certificate, keyPEM: opensslImported.keyPEM)
            return
        }

        throw CertificateAuthorityError.pkcs12ImportFailed("Unable to persist imported PKCS#12 private key")
        #else
        throw CertificateAuthorityError.pkcs12Unsupported
        #endif
    }

    public func serverTLSContext(for leaf: LeafConfig) async throws -> NIOSSLContext {
        try await ensureRootCA()

        let cacheKey = leaf.host + "|" + leaf.alpnProtocols.joined(separator: ",")
        if let cached = leafContextCache[cacheKey], Date().timeIntervalSince(cached.createdAt) < cacheTTL {
            return cached.sslContext
        }

        guard let caCert = rootCertificate, let caKey = rootPrivateKey else {
            throw CertificateAuthorityError.invalidPEM
        }

        let leafKey = try await ensureLeafKey()
        let leafCert = try generateLeafCertificate(
            host: leaf.host,
            caCert: caCert,
            caKey: caKey,
            leafPublicKey: leafKey.publicKey
        )

        let certDER = try leafCert.serializeAsDER()
        let keyPEM = try leafKey.serializeAsPEM().pemString

        let nioCert = try NIOSSLCertificate(bytes: Array(certDER), format: .der)
        let nioKey = try NIOSSLPrivateKey(bytes: Array(keyPEM.utf8), format: .pem)

        var tls = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(nioCert)],
            privateKey: .privateKey(nioKey)
        )
        tls.applicationProtocols = leaf.alpnProtocols
        tls.certificateVerification = .none
        tls.renegotiationSupport = .none

        let context = try NIOSSLContext(configuration: tls)
        leafContextCache[cacheKey] = CacheEntry(createdAt: Date(), sslContext: context)
        return context
    }

    // MARK: - Internals

    nonisolated private static func ensureDirectoryExists(_ url: URL) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw CertificateAuthorityError.invalidBaseDirectory
        }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw CertificateAuthorityError.failedToCreateDirectory(url)
        }
    }

    private func ensureRootCA(customCommonName: String? = nil) async throws {
        if rootCertificate != nil, rootPrivateKey != nil {
            return
        }

        if FileManager.default.fileExists(atPath: rootCertURL.path),
           FileManager.default.fileExists(atPath: rootKeyURL.path) {
            try loadRootCAFromDisk()
            if rootCertificate != nil, rootPrivateKey != nil {
                return
            }
        }

        let commonName = customCommonName ?? "ProxyCore CA"
        let rsaKey = try _CryptoExtras._RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsaKey)
        let publicKey = key.publicKey
        let subject = try DistinguishedName {
            CommonName(commonName)
            OrganizationName("ProxyCore")
        }

        let extensions = try Certificate.Extensions {
            try Certificate.Extension(BasicConstraints.isCertificateAuthority(maxPathLength: nil), critical: true)
            try Certificate.Extension(
                KeyUsage(digitalSignature: true, keyCertSign: true, cRLSign: true),
                critical: true
            )
            SubjectKeyIdentifier(hash: publicKey)
        }

        // Allow a small clock skew window: clients may reject leaf/root certs that become valid "now"
        // if their clock is slightly behind the proxy host.
        let now = Date()
        let notBefore = now.addingTimeInterval(-60 * 5)
        let notAfter = Calendar.current.date(byAdding: .day, value: 825, to: now) ?? now.addingTimeInterval(825 * 24 * 3600)

        let serial = Certificate.SerialNumber()

        let cert = try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: key
        )

        rootCertificate = cert
        rootPrivateKey = key

        try persistRootCA(cert: cert, keyPEM: rsaKey.pemRepresentation)
    }

    private func ensureRootCA() async throws {
        try await ensureRootCA(customCommonName: nil)
    }

    private func loadRootCAFromDisk() throws {
        let certPEM: String
        let keyPEM: String
        do {
            certPEM = try String(contentsOf: rootCertURL, encoding: .utf8)
            keyPEM = try String(contentsOf: rootKeyURL, encoding: .utf8)
        } catch {
            throw CertificateAuthorityError.failedToReadFile(rootCertURL)
        }

        let certDoc = try PEMDocument(pemString: certPEM)
        let cert = try Certificate(derEncoded: certDoc.derBytes)
        let key = try Certificate.PrivateKey(pemEncoded: keyPEM)

        rootCertificate = cert
        rootPrivateKey = key
    }

    private func persistRootCA(cert: Certificate, keyPEM: String) throws {
        let certPEM: String
        do {
            certPEM = try cert.serializeAsPEM().pemString
        } catch {
            throw CertificateAuthorityError.certificateGenerationFailed("Unable to serialize root certificate: \(error)")
        }

        do {
            try certPEM.write(to: rootCertURL, atomically: true, encoding: .utf8)
        } catch {
            throw CertificateAuthorityError.failedToWriteFile(rootCertURL)
        }

        do {
            try keyPEM.write(to: rootKeyURL, atomically: true, encoding: .utf8)
        } catch {
            throw CertificateAuthorityError.failedToWriteFile(rootKeyURL)
        }
    }

    private func ensureLeafKey() async throws -> Certificate.PrivateKey {
        if let leafPrivateKey {
            return leafPrivateKey
        }
        let rsaKey = try _CryptoExtras._RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsaKey)
        leafPrivateKey = key
        return key
    }

    private func generateLeafCertificate(
        host: String,
        caCert: Certificate,
        caKey: Certificate.PrivateKey,
        leafPublicKey: Certificate.PublicKey
    ) throws -> Certificate {
        let subject = try DistinguishedName {
            CommonName(host)
            OrganizationName("ProxyCore")
        }

        // Allow a small clock skew window for leaf certificates too.
        let now = Date()
        let notBefore = now.addingTimeInterval(-60 * 5)
        let notAfter = Calendar.current.date(byAdding: .day, value: 365, to: now) ?? now.addingTimeInterval(365 * 24 * 3600)

        let serial = Certificate.SerialNumber()

        let extensions = try Certificate.Extensions {
            try Certificate.Extension(BasicConstraints.notCertificateAuthority, critical: true)
            try Certificate.Extension(KeyUsage(digitalSignature: true, keyEncipherment: true), critical: true)
            try ExtendedKeyUsage([.serverAuth])
            SubjectAlternativeNames([Self.generalNameForHost(host)])
            AuthorityKeyIdentifier(
                keyIdentifier: SubjectKeyIdentifier(hash: caCert.publicKey).keyIdentifier
            )
            SubjectKeyIdentifier(hash: leafPublicKey)
        }

        return try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: leafPublicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: caCert.issuer,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: caKey
        )
    }
}

private extension Certificate {
    func serializeAsDER() throws -> [UInt8] {
        var serializer = DER.Serializer()
        try self.serialize(into: &serializer)
        return serializer.serializedBytes
    }
}

// MARK: - PKCS#12 helpers

#if canImport(Security)
private extension CertificateAuthority {
    static func secErrorMessage(_ status: OSStatus) -> String {
        if let msg = SecCopyErrorMessageString(status, nil) as String? {
            return msg
        }
        return "OSStatus \(status)"
    }

    static func importPKCS12WithSecurity(data: Data, password: String) throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey) {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]

        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else {
            throw CertificateAuthorityError.pkcs12ImportFailed(secErrorMessage(status))
        }

        guard let array = items as? [[String: Any]], let first = array.first else {
            throw CertificateAuthorityError.pkcs12ImportFailed("Empty PKCS#12")
        }

        guard let identityAny = first[kSecImportItemIdentity as String] else {
            throw CertificateAuthorityError.pkcs12ImportFailed("No identity found")
        }
        guard CFGetTypeID(identityAny as CFTypeRef) == SecIdentityGetTypeID() else {
            throw CertificateAuthorityError.pkcs12ImportFailed("Invalid identity type")
        }
        let identity = identityAny as! SecIdentity

        var secCert: SecCertificate?
        let statusCert = SecIdentityCopyCertificate(identity, &secCert)
        guard statusCert == errSecSuccess, let secCert else {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to extract certificate: \(secErrorMessage(statusCert))")
        }

        let certData = SecCertificateCopyData(secCert) as Data
        let certificate = try Certificate(derEncoded: Array(certData))

        var secKey: SecKey?
        let statusKey = SecIdentityCopyPrivateKey(identity, &secKey)
        guard statusKey == errSecSuccess, let secKey else {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to extract private key: \(secErrorMessage(statusKey))")
        }

        let privateKey = try bestEffortPrivateKeyFromSecKey(secKey)
        return (certificate: certificate, privateKey: privateKey)
    }

    static func bestEffortPrivateKeyFromSecKey(_ secKey: SecKey) throws -> Certificate.PrivateKey {
        // We prefer to keep our CA key in a crypto-backed representation (i.e. not SecKey-backed) so that
        // we can reliably serialize it to PEM (needed by NIOSSL and for on-disk persistence).
        if #available(macOS 11.0, iOS 14, tvOS 14, watchOS 7, macCatalyst 14, visionOS 1.0, *) {
            var error: Unmanaged<CFError>?
            if let keyData = SecKeyCopyExternalRepresentation(secKey, &error) as Data? {
                let attrs = SecKeyCopyAttributes(secKey) as NSDictionary? ?? [:]
                let keyType = attrs[kSecAttrKeyType as String] as? String

                if keyType == (kSecAttrKeyTypeRSA as String) {
                    let doc = PEMDocument(type: "RSA PRIVATE KEY", derBytes: Array(keyData))
                    return try Certificate.PrivateKey(pemDocument: doc)
                }

                if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
                    let doc = PEMDocument(type: "EC PRIVATE KEY", derBytes: Array(keyData))
                    return try Certificate.PrivateKey(pemDocument: doc)
                }
            }
        }

        // Fallback: keep the SecKey-backed representation (may not be serializable depending on key ACL/attributes).
        return try Certificate.PrivateKey(secKey)
    }

    static func exportPKCS12WithSecurity(certificate: Certificate, privateKey: Certificate.PrivateKey, password: String) throws -> Data {
        #if os(macOS)
        let certDER = try certificate.serializeAsDER()
        guard let secCert = SecCertificateCreateWithData(nil, Data(certDER) as CFData) else {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to create SecCertificate")
        }

        // Convert our key to a SecKey via SecItemImport (avoids having to parse PKCS#8/SEC1 formats here).
        let keyPEM = try privateKey.serializeAsPEM().pemString
        guard let keyData = keyPEM.data(using: .utf8) else {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to encode key as UTF-8")
        }

        var inputFormat: SecExternalFormat = .formatUnknown
        var itemType: SecExternalItemType = .itemTypeUnknown
        var outItems: CFArray?
        let statusImport = SecItemImport(
            keyData as CFData,
            nil,
            &inputFormat,
            &itemType,
            SecItemImportExportFlags(),
            nil,
            nil,
            &outItems
        )
        guard statusImport == errSecSuccess else {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to import key: \(secErrorMessage(statusImport))")
        }

        let secKey = (outItems as? [Any])?.compactMap { item -> SecKey? in
            guard CFGetTypeID(item as CFTypeRef) == SecKeyGetTypeID() else {
                return nil
            }
            return .some(item as! SecKey)
        }.first
        guard let secKey else {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to locate imported SecKey")
        }

        let exportItems: NSArray = [secKey, secCert]
        var params = SecItemImportExportKeyParameters()
        params.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        params.flags = SecKeyImportExportFlags()

        let passphrase = password as CFString
        params.passphrase = Unmanaged.passUnretained(passphrase)

        var exported: CFData?
        let statusExport = SecItemExport(
            exportItems,
            .formatPKCS12,
            SecItemImportExportFlags(),
            &params,
            &exported
        )
        guard statusExport == errSecSuccess, let exported else {
            throw CertificateAuthorityError.pkcs12ExportFailed(secErrorMessage(statusExport))
        }
        return exported as Data
        #else
        throw CertificateAuthorityError.pkcs12Unsupported
        #endif
    }
}
#endif

private extension CertificateAuthority {
    func exportPKCS12WithOpenSSL(password: String) async throws -> Data {
        #if os(macOS)
        // Use the persisted PEM files as inputs for `openssl pkcs12 -export ...`.
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appending(path: "ProxyCore-\(UUID().uuidString).p12", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        proc.arguments = [
            "pkcs12",
            "-export",
            "-inkey", rootKeyURL.path,
            "-in", rootCertURL.path,
            "-out", outURL.path,
            "-passout", "pass:\(password)",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to launch openssl: \(error)")
        }

        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CertificateAuthorityError.pkcs12ExportFailed(err.isEmpty ? "openssl exited with \(proc.terminationStatus)" : err)
        }

        do {
            return try Data(contentsOf: outURL)
        } catch {
            throw CertificateAuthorityError.pkcs12ExportFailed("Unable to read openssl output: \(error)")
        }
        #else
        throw CertificateAuthorityError.pkcs12Unsupported
        #endif
    }

    func importPKCS12WithOpenSSL(data: Data, password: String) async throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey, keyPEM: String) {
        #if os(macOS)
        let tmp = FileManager.default.temporaryDirectory
        let inURL = tmp.appending(path: "ProxyCore-\(UUID().uuidString).p12", directoryHint: .notDirectory)
        let outURL = tmp.appending(path: "ProxyCore-\(UUID().uuidString).pem", directoryHint: .notDirectory)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        do {
            try data.write(to: inURL, options: [.atomic])
        } catch {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to write temp PKCS#12: \(error)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        proc.arguments = [
            "pkcs12",
            "-in", inURL.path,
            "-nodes",
            "-passin", "pass:\(password)",
            "-out", outURL.path,
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to launch openssl: \(error)")
        }

        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CertificateAuthorityError.pkcs12ImportFailed(err.isEmpty ? "openssl exited with \(proc.terminationStatus)" : err)
        }

        let pemString: String
        do {
            pemString = try String(contentsOf: outURL, encoding: .utf8)
        } catch {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to read openssl output: \(error)")
        }

        let docs: [PEMDocument]
        do {
            docs = try PEMDocument.parseMultiple(pemString: pemString)
        } catch {
            throw CertificateAuthorityError.pkcs12ImportFailed("Unable to parse openssl PEM output: \(error)")
        }

        guard let certDoc = docs.first(where: { $0.discriminator == "CERTIFICATE" }) else {
            throw CertificateAuthorityError.pkcs12ImportFailed("No CERTIFICATE found in PKCS#12")
        }
        guard let keyDoc = docs.first(where: { $0.discriminator.contains("PRIVATE KEY") }) else {
            throw CertificateAuthorityError.pkcs12ImportFailed("No PRIVATE KEY found in PKCS#12")
        }

        let certificate = try Certificate(derEncoded: certDoc.derBytes)
        let privateKey = try Certificate.PrivateKey(pemDocument: keyDoc)
        return (certificate: certificate, privateKey: privateKey, keyPEM: keyDoc.pemString)
        #else
        throw CertificateAuthorityError.pkcs12Unsupported
        #endif
    }
}

private extension CertificateAuthority {
    static func generalNameForHost(_ host: String) -> GeneralName {
        if let ipv4 = host.asIPv4Octets() {
            return .ipAddress(ASN1OctetString(contentBytes: ipv4[...]))
        }
        if let ipv6 = host.asIPv6Octets() {
            return .ipAddress(ASN1OctetString(contentBytes: ipv6[...]))
        }
        return .dnsName(host)
    }
}

private extension String {
    func asIPv4Octets() -> [UInt8]? {
        var addr = in_addr()
        let ok = self.withCString { cstr in
            inet_pton(AF_INET, cstr, &addr)
        }
        guard ok == 1 else { return nil }
        // `in_addr.s_addr` is already stored in network byte order.
        return withUnsafeBytes(of: addr.s_addr) { Array($0) }
    }

    func asIPv6Octets() -> [UInt8]? {
        var addr = in6_addr()
        let ok = self.withCString { cstr in
            inet_pton(AF_INET6, cstr, &addr)
        }
        guard ok == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }
}
