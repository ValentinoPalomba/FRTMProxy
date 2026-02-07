import XCTest
import SwiftASN1
import X509
import _CryptoExtras

final class CryptoKeySerializationTests: XCTestCase {
    func testRSAPrivateKeyWrapSerializesAsPEM() throws {
        let rsa = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsa)

        XCTAssertNotEqual(String(describing: key), "SecKey")

        let pem = try key.serializeAsPEM().pemString
        XCTAssertTrue(pem.contains("BEGIN"))
        XCTAssertTrue(pem.contains("PRIVATE KEY"))

        // Ensure we can parse the PEM back.
        _ = try Certificate.PrivateKey(pemEncoded: pem)
    }

    func testRSAPrivateKeyWrapSerializesAsPEMInAsyncContext() async throws {
        let rsa = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsa)
        XCTAssertNotEqual(String(describing: key), "SecKey")
        _ = try key.serializeAsPEM().pemString
    }

    func testRSAPrivateKeyCanSignCertificateAndStillSerializes() throws {
        let rsa = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let key = Certificate.PrivateKey(rsa)

        let subject = try DistinguishedName {
            CommonName("ProxyCore Test CA")
            OrganizationName("ProxyCore")
        }

        let publicKey = key.publicKey
        let extensions = try Certificate.Extensions {
            try Certificate.Extension(BasicConstraints.isCertificateAuthority(maxPathLength: nil), critical: true)
            try Certificate.Extension(KeyUsage(digitalSignature: true, keyCertSign: true, cRLSign: true), critical: true)
            SubjectKeyIdentifier(hash: publicKey)
        }

        let now = Date()
        let cert = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: publicKey,
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(3600),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: key
        )
        XCTAssertNotNil(cert)

        XCTAssertNotEqual(String(describing: key), "SecKey")
        _ = try key.serializeAsPEM().pemString
    }
}
