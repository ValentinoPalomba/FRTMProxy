import CryptoKit
import Foundation

/// Production captures use Keychain-backed storage. Debug UI fixtures explicitly
/// opt into disposable storage and a fixture key so they never touch user data.
enum CaptureStorageConfiguration {
    static var preferences: UserDefaults {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["FRTM_UI_TEST_STORAGE"], !path.isEmpty {
            let suite = "FRTMProxy.Settings.Fixture." + URL(fileURLWithPath: path).lastPathComponent
            return UserDefaults(suiteName: suite) ?? .standard
        }
        #endif
        return .standard
    }

    #if DEBUG
    private static let unitTestRoot = FileManager.default.temporaryDirectory
        .appending(path: "frtm-unit-capture-\(UUID().uuidString)", directoryHint: .isDirectory)

    private static var usesUnitTestStorage: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["FRTM_ISOLATED_CAPTURE_TESTS"] == "1"
    }

    private struct FixtureKeyProvider: SessionEncryptionKeyProviding {
        func loadOrCreateKey() throws -> SymmetricKey {
            SymmetricKey(data: Data(repeating: 0x42, count: 32))
        }
    }
    #endif

    static var root: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["FRTM_UI_TEST_STORAGE"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if usesUnitTestStorage { return unitTestRoot }
        #endif
        return URL.applicationSupportDirectory
    }

    static var keyProvider: any SessionEncryptionKeyProviding {
        #if DEBUG
        if usesUnitTestStorage || ProcessInfo.processInfo.environment["FRTM_UI_TEST_STORAGE"]?.isEmpty == false {
            return FixtureKeyProvider()
        }
        #endif
        return KeychainSessionEncryptionKeyProvider()
    }
}
