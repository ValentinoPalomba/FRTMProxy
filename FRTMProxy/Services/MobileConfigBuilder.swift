import Foundation

struct MobileConfigBuilder {
    struct Payload {
        let displayName: String
        let organization: String
        let wifiSSID: String
        let proxyHost: String
        let proxyPort: Int
        let rootCADER: Data
    }

    func build(_ payload: Payload) throws -> Data {
        let profileUUID = UUID().uuidString

        let proxyPayloadUUID = UUID().uuidString
        let certificatePayloadUUID = UUID().uuidString

        let wifiPayload: [String: Any] = [
            "PayloadType": "com.apple.wifi.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "io.frtmproxy.profile.\(profileUUID).wifi",
            "PayloadUUID": proxyPayloadUUID,
            "PayloadDisplayName": "FRTMProxy Wi‑Fi Proxy",
            "SSID_STR": payload.wifiSSID,
            "HIDDEN_NETWORK": false,
            "EncryptionType": "Any",
            "AutoJoin": true,
            "ProxyType": "Manual",
            "ProxyServer": payload.proxyHost,
            "ProxyServerPort": payload.proxyPort,
            "ProxyCaptiveLoginAllowed": true
        ]

        let certificatePayload: [String: Any] = [
            "PayloadType": "com.apple.security.root",
            "PayloadVersion": 1,
            "PayloadIdentifier": "io.frtmproxy.profile.\(profileUUID).ca",
            "PayloadUUID": certificatePayloadUUID,
            "PayloadDisplayName": "FRTMProxy Root CA",
            "PayloadContent": payload.rootCADER
        ]

        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "io.frtmproxy.profile.\(profileUUID)",
            "PayloadUUID": profileUUID,
            "PayloadDisplayName": payload.displayName,
            "PayloadDescription": "Configura il proxy (solo per la rete Wi‑Fi selezionata) e installa la Root CA di FRTMProxy per intercettare traffico HTTP/S.",
            "PayloadOrganization": payload.organization,
            "PayloadContent": [wifiPayload, certificatePayload]
        ]

        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
