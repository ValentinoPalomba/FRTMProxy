import Foundation
import Security
import SystemConfiguration

enum MacOSProxyOverrideError: LocalizedError {
    case authorizationFailed(OSStatus)
    case preferencesUnavailable
    case commitFailed
    case applyFailed

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let status):
            return "macOS proxy override failed: authorization error (\(status))."
        case .preferencesUnavailable:
            return "macOS proxy override failed: unable to access network preferences."
        case .commitFailed:
            return "macOS proxy override failed: unable to save proxy settings."
        case .applyFailed:
            return "macOS proxy override failed: unable to apply proxy settings."
        }
    }
}

struct MacOSProxySnapshot: Codable {
    struct ProxySettings: Codable {
        let enabled: Bool
        let host: String?
        let port: Int?
    }

    struct ServiceSettings: Codable {
        let http: ProxySettings
        let https: ProxySettings
    }

    var services: [String: ServiceSettings]
}

actor MacOSProxyOverrideManager {
    static let shared = MacOSProxyOverrideManager()

    private let snapshotKey = "settings.macosProxyOverride.snapshot"
    private let defaults = UserDefaults.standard
    private let overrideHosts: Set<String> = ["localhost", "127.0.0.1"]

    func enableProxy(host: String, port: Int) throws {
        let (preferences, authorization) = try authorizedPreferences()
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let services = (SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]) ?? []
        var snapshot = loadSnapshot() ?? MacOSProxySnapshot(services: [:])
        var snapshotUpdated = false

        for service in services {
            guard SCNetworkServiceGetEnabled(service) else { continue }
            guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else { continue }
            guard let proxyProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { continue }

            let currentConfig = SCNetworkProtocolGetConfiguration(proxyProtocol) as? [String: Any] ?? [:]
            if snapshot.services[serviceID] == nil {
                let serviceSnapshot = MacOSProxySnapshot.ServiceSettings(
                    http: proxySettings(from: currentConfig,
                                        enableKey: kSCPropNetProxiesHTTPEnable,
                                        hostKey: kSCPropNetProxiesHTTPProxy,
                                        portKey: kSCPropNetProxiesHTTPPort),
                    https: proxySettings(from: currentConfig,
                                         enableKey: kSCPropNetProxiesHTTPSEnable,
                                         hostKey: kSCPropNetProxiesHTTPSProxy,
                                         portKey: kSCPropNetProxiesHTTPSPort)
                )
                snapshot.services[serviceID] = serviceSnapshot
                snapshotUpdated = true
            }

            var updatedConfig = currentConfig
            applyOverride(host: host, port: port, to: &updatedConfig)
            SCNetworkProtocolSetConfiguration(proxyProtocol, updatedConfig as CFDictionary)
        }

        try commitChanges(preferences)
        if snapshotUpdated {
            persistSnapshot(snapshot)
        }
    }

    func disableProxy() throws {
        let (preferences, authorization) = try authorizedPreferences()
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let services = (SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]) ?? []

        if let snapshot = loadSnapshot() {
            for service in services {
                guard SCNetworkServiceGetEnabled(service) else { continue }
                guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else { continue }
                guard let serviceSnapshot = snapshot.services[serviceID] else { continue }
                guard let proxyProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { continue }

                var config = SCNetworkProtocolGetConfiguration(proxyProtocol) as? [String: Any] ?? [:]
                applySnapshot(serviceSnapshot, to: &config)
                SCNetworkProtocolSetConfiguration(proxyProtocol, config as CFDictionary)
            }

            try commitChanges(preferences)
            clearSnapshot()
            return
        }

        var didUpdate = false
        for service in services {
            guard SCNetworkServiceGetEnabled(service) else { continue }
            guard let proxyProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { continue }

            var config = SCNetworkProtocolGetConfiguration(proxyProtocol) as? [String: Any] ?? [:]
            if disableOverrideIfPresent(in: &config) {
                didUpdate = true
                SCNetworkProtocolSetConfiguration(proxyProtocol, config as CFDictionary)
            }
        }

        if didUpdate {
            try commitChanges(preferences)
        }
    }

    private func authorizedPreferences() throws -> (SCPreferences, AuthorizationRef) {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authorization)
        guard createStatus == errAuthorizationSuccess, let authorization else {
            throw MacOSProxyOverrideError.authorizationFailed(createStatus)
        }
        var shouldFreeAuthorization = true
        defer {
            if shouldFreeAuthorization {
                AuthorizationFree(authorization, [.destroyRights])
            }
        }

        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let rightsStatus = "system.preferences.network".withCString { namePointer in
            var authItem = AuthorizationItem(name: namePointer, valueLength: 0, value: nil, flags: 0)
            var authRights = AuthorizationRights(count: 1, items: &authItem)
            return AuthorizationCopyRights(authorization, &authRights, nil, flags, nil)
        }
        guard rightsStatus == errAuthorizationSuccess else {
            throw MacOSProxyOverrideError.authorizationFailed(rightsStatus)
        }

        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil,
            "io.frtmproxy" as CFString,
            nil,
            authorization
        ) else {
            throw MacOSProxyOverrideError.preferencesUnavailable
        }

        shouldFreeAuthorization = false
        return (preferences, authorization)
    }

    private func commitChanges(_ preferences: SCPreferences) throws {
        guard SCPreferencesCommitChanges(preferences) else {
            throw MacOSProxyOverrideError.commitFailed
        }
        guard SCPreferencesApplyChanges(preferences) else {
            throw MacOSProxyOverrideError.applyFailed
        }
    }

    private func proxySettings(
        from config: [String: Any],
        enableKey: CFString,
        hostKey: CFString,
        portKey: CFString
    ) -> MacOSProxySnapshot.ProxySettings {
        let enabled = (config[enableKey as String] as? NSNumber)?.boolValue ?? false
        let host = config[hostKey as String] as? String
        let port = (config[portKey as String] as? NSNumber)?.intValue
        return MacOSProxySnapshot.ProxySettings(enabled: enabled, host: host, port: port)
    }

    private func applySnapshot(_ snapshot: MacOSProxySnapshot.ServiceSettings, to config: inout [String: Any]) {
        applyProxySettings(
            snapshot.http,
            enableKey: kSCPropNetProxiesHTTPEnable,
            hostKey: kSCPropNetProxiesHTTPProxy,
            portKey: kSCPropNetProxiesHTTPPort,
            to: &config
        )
        applyProxySettings(
            snapshot.https,
            enableKey: kSCPropNetProxiesHTTPSEnable,
            hostKey: kSCPropNetProxiesHTTPSProxy,
            portKey: kSCPropNetProxiesHTTPSPort,
            to: &config
        )
    }

    private func applyOverride(host: String, port: Int, to config: inout [String: Any]) {
        applyProxySettings(
            MacOSProxySnapshot.ProxySettings(enabled: true, host: host, port: port),
            enableKey: kSCPropNetProxiesHTTPEnable,
            hostKey: kSCPropNetProxiesHTTPProxy,
            portKey: kSCPropNetProxiesHTTPPort,
            to: &config
        )
        applyProxySettings(
            MacOSProxySnapshot.ProxySettings(enabled: true, host: host, port: port),
            enableKey: kSCPropNetProxiesHTTPSEnable,
            hostKey: kSCPropNetProxiesHTTPSProxy,
            portKey: kSCPropNetProxiesHTTPSPort,
            to: &config
        )
    }

    private func applyProxySettings(
        _ settings: MacOSProxySnapshot.ProxySettings,
        enableKey: CFString,
        hostKey: CFString,
        portKey: CFString,
        to config: inout [String: Any]
    ) {
        config[enableKey as String] = settings.enabled ? 1 : 0

        if let host = settings.host {
            config[hostKey as String] = host
        } else {
            config.removeValue(forKey: hostKey as String)
        }

        if let port = settings.port {
            config[portKey as String] = port
        } else {
            config.removeValue(forKey: portKey as String)
        }
    }

    private func disableOverrideIfPresent(in config: inout [String: Any]) -> Bool {
        let httpChanged = clearProxyIfOverride(
            enableKey: kSCPropNetProxiesHTTPEnable,
            hostKey: kSCPropNetProxiesHTTPProxy,
            portKey: kSCPropNetProxiesHTTPPort,
            config: &config
        )
        let httpsChanged = clearProxyIfOverride(
            enableKey: kSCPropNetProxiesHTTPSEnable,
            hostKey: kSCPropNetProxiesHTTPSProxy,
            portKey: kSCPropNetProxiesHTTPSPort,
            config: &config
        )
        return httpChanged || httpsChanged
    }

    private func clearProxyIfOverride(
        enableKey: CFString,
        hostKey: CFString,
        portKey: CFString,
        config: inout [String: Any]
    ) -> Bool {
        guard let host = config[hostKey as String] as? String,
              overrideHosts.contains(host) else {
            return false
        }
        config[enableKey as String] = 0
        config.removeValue(forKey: hostKey as String)
        config.removeValue(forKey: portKey as String)
        return true
    }

    private func loadSnapshot() -> MacOSProxySnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(MacOSProxySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func persistSnapshot(_ snapshot: MacOSProxySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private func clearSnapshot() {
        defaults.removeObject(forKey: snapshotKey)
    }
}
