import Foundation

extension ProxyConfiguration.HostFilter {
    /// Mirrors ProxyPin semantics: if whitelist is enabled, everything not matching is filtered.
    /// If blacklist is enabled, anything matching is filtered.
    func shouldFilter(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }

        if whitelistEnabled {
            // If whitelist is enabled, only whitelisted hosts are allowed.
            return whitelistPatterns.compactMap(Self.compile).allSatisfy { !$0(host) }
        }

        if blacklistEnabled {
            return blacklistPatterns.compactMap(Self.compile).contains { $0(host) }
        }

        return false
    }

    private static func compile(_ pattern: String) -> ((String) -> Bool)? {
        guard !pattern.isEmpty else { return nil }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return { input in
                let range = NSRange(input.startIndex..<input.endIndex, in: input)
                return regex.firstMatch(in: input, range: range) != nil
            }
        } catch {
            return nil
        }
    }
}

