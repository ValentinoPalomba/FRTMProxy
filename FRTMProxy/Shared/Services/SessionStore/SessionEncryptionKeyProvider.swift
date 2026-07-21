import CryptoKit
import Foundation
import Security

protocol SessionEncryptionKeyProviding: Sendable {
    func loadOrCreateKey() throws -> SymmetricKey
}

enum SessionEncryptionKeyError: Error, Equatable {
    case keychain(OSStatus)
    case invalidKeyMaterial
}

struct KeychainSessionEncryptionKeyProvider: SessionEncryptionKeyProviding {
    private let service: String
    private let account: String

    init(
        service: String = "com.frtmproxy.capture-sessions",
        account: String = "payload-encryption-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKey() {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let raced = try readKey() {
            return SymmetricKey(data: raced)
        }
        guard status == errSecSuccess else {
            throw SessionEncryptionKeyError.keychain(status)
        }
        return key
    }

    private func readKey() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SessionEncryptionKeyError.keychain(status)
        }
        guard let data = result as? Data, data.count == 32 else {
            throw SessionEncryptionKeyError.invalidKeyMaterial
        }
        return data
    }
}
