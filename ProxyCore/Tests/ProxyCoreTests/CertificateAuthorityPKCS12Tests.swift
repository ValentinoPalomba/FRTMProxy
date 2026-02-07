import XCTest
@testable import ProxyCore

final class CertificateAuthorityPKCS12Tests: XCTestCase {
    func testExportImportPKCS12RoundTripRestoresRootCA() async throws {
        #if os(macOS)
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("ProxyCoreCA-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let ca = try CertificateAuthority(baseDirectory: baseDir)

        let originalDER = try await ca.rootCertificateDER()
        let pkcs12 = try await ca.exportRootCAPKCS12(password: "test-pass")
        XCTAssertFalse(pkcs12.isEmpty)

        try await ca.generateNewRootCA(commonName: "ProxyCore CA (temp)")
        let changedDER = try await ca.rootCertificateDER()
        XCTAssertNotEqual(originalDER, changedDER)

        try await ca.importRootCAPKCS12(pkcs12, password: "test-pass")
        let restoredDER = try await ca.rootCertificateDER()
        XCTAssertEqual(originalDER, restoredDER)
        #else
        throw XCTSkip("PKCS#12 round-trip is only supported on macOS")
        #endif
    }
}
