import Foundation

struct MitmproxyCertificateLoader {
    enum LoaderError: LocalizedError {
        case certificateMissing(basePath: String)

        var errorDescription: String? {
            switch self {
            case .certificateMissing(let path):
                return "Root CA certificate not found in \(path). Start the proxy once to generate it."
            }
        }
    }

    func loadRootCADER() throws -> Data {
        let cerURL = CertificateManager.shared.caCertificateURL()

        guard FileManager.default.fileExists(atPath: cerURL.path) else {
            // Try to generate it if missing
            try? CertificateManager.shared.ensureRootCA()
            if !FileManager.default.fileExists(atPath: cerURL.path) {
                throw LoaderError.certificateMissing(basePath: cerURL.deletingLastPathComponent().path)
            }
        }

        return try Data(contentsOf: cerURL)
    }
}
