import Foundation
import Security

struct UpstreamProxyPasswordStore {
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrService: "com.valentinopalomba.frtmproxy.upstream",
         kSecAttrAccount: "upstream-password"]
    }

    func load() throws -> String {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let password = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return password
    }

    func save(_ password: String) throws {
        let status: OSStatus
        if password.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let data = Data(password.utf8)
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
            if updateStatus == errSecItemNotFound {
                var request = query
                request[kSecValueData] = data
                request[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(request as CFDictionary, nil)
            } else {
                status = updateStatus
            }
        }
        guard status == errSecSuccess || (password.isEmpty && status == errSecItemNotFound) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
