import Foundation
import CoreWLAN
import Darwin

enum LocalNetworkInfo {
    static func currentWiFiSSID() -> String? {
        let raw = CWWiFiClient.shared().interface()?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        let lowercased = raw.lowercased()
        if lowercased.contains("redacted") {
            return nil
        }
        return raw
    }

    static func primaryIPv4Address(preferredInterfaces: [String] = ["en0"]) -> String? {
        guard let addresses = ipv4AddressesByInterface(), !addresses.isEmpty else { return nil }
        for interface in preferredInterfaces {
            if let address = addresses[interface] {
                return address
            }
        }
        return addresses.values.first
    }

    private static func ipv4AddressesByInterface() -> [String: String]? {
        var result: [String: String] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = ptr.pointee.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            guard isUp, !isLoopback else { continue }

            guard let sa = ptr.pointee.ifa_addr else { continue }
            guard sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(sa.pointee.sa_len)
            let nameInfoResult = getnameinfo(
                sa,
                length,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard nameInfoResult == 0 else { continue }

            let interface = String(cString: ptr.pointee.ifa_name)
            result[interface] = String(cString: hostBuffer)
        }

        return result
    }
}
