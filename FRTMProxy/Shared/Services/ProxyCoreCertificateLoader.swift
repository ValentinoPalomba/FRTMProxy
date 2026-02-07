import Foundation
import ProxyCore

/// Loads (and if missing, generates) the Root CA used by ProxyCore.
///
/// We prefer going through `CertificateAuthority` instead of reading `ca.crt` directly so that
/// the device pairing flow works even before the proxy has been started once.
struct ProxyCoreCertificateLoader {
    enum LoaderError: LocalizedError {
        case missingRootCertificate

        var errorDescription: String? {
            switch self {
            case .missingRootCertificate:
                return "ProxyCore Root CA is not available."
            }
        }
    }

    func loadRootCADER() async throws -> Data {
        let paths = try ProxyConfiguration.Paths.defaultPaths()
        let ca = try CertificateAuthority(baseDirectory: paths.baseDirectory)
        let der = try await ca.rootCertificateDER()
        guard !der.isEmpty else { throw LoaderError.missingRootCertificate }
        return der
    }
}

