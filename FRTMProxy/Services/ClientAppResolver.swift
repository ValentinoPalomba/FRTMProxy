import AppKit
import Foundation

actor ClientAppResolver {
    private struct CacheKey: Hashable {
        let clientPort: Int
        let proxyPort: Int
    }

    private struct CacheEntry: Sendable {
        let app: FlowClientApp?
        let cachedAt: Date
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private let ttl: TimeInterval = 10

    func resolve(clientPort: Int, proxyPort: Int) async -> FlowClientApp? {
        let key = CacheKey(clientPort: clientPort, proxyPort: proxyPort)
        if let cached = cache[key], Date().timeIntervalSince(cached.cachedAt) < ttl {
            return cached.app
        }

        let app = await resolveFresh(clientPort: clientPort, proxyPort: proxyPort)
        cache[key] = CacheEntry(app: app, cachedAt: Date())
        return app
    }

    private func resolveFresh(clientPort: Int, proxyPort: Int) async -> FlowClientApp? {
        guard clientPort > 0, proxyPort > 0 else { return nil }
        guard let lsofPath = lsofExecutablePath() else { return nil }

        let output = await runLsof(lsofPath: lsofPath, clientPort: clientPort)
        guard let match = parseLsof(output: output, clientPort: clientPort, proxyPort: proxyPort) else {
            return nil
        }

        let pid = match.pid
        let command = match.command

        let appInfo = await MainActor.run {
            let running = NSRunningApplication(processIdentifier: pid)
            let bundleIdentifier = running?.bundleIdentifier
            let resolvedURL = running?.bundleURL
                ?? (bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })

            let displayName = (running?.localizedName?.isEmpty == false)
                ? (running?.localizedName ?? command)
                : command

            return (
                bundleIdentifier: bundleIdentifier,
                bundleURL: resolvedURL?.absoluteString,
                displayName: displayName
            )
        }

        let idCandidate = appInfo.bundleIdentifier?.isEmpty == false
            ? (appInfo.bundleIdentifier ?? "")
            : (appInfo.bundleURL?.isEmpty == false ? (appInfo.bundleURL ?? "") : appInfo.displayName)

        let normalizedID = FlowClientApp.normalizedID(idCandidate)
        guard !normalizedID.isEmpty else { return nil }

        return FlowClientApp(
            id: normalizedID,
            displayName: appInfo.displayName,
            bundleIdentifier: appInfo.bundleIdentifier,
            bundleURL: appInfo.bundleURL,
            pid: Int(pid)
        )
    }

    private func lsofExecutablePath() -> String? {
        let candidates = ["/usr/sbin/lsof", "/usr/bin/lsof"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func runLsof(lsofPath: String, clientPort: Int) async -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsofPath)
        task.arguments = ["-nP", "-iTCP:\(clientPort)", "-sTCP:ESTABLISHED", "-Fpcn"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return ""
        }

        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private struct LsofMatch {
        let pid: pid_t
        let command: String
    }

    private func parseLsof(output: String, clientPort: Int, proxyPort: Int) -> LsofMatch? {
        var currentPid: pid_t?
        var currentCommand: String?

        for line in output.split(separator: "\n") {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                if let parsed = Int32(value) {
                    currentPid = pid_t(parsed)
                } else {
                    currentPid = nil
                }
            case "c":
                currentCommand = value
            case "n":
                guard let currentPid, let currentCommand else { continue }
                if matchesClientToProxy(name: value, clientPort: clientPort, proxyPort: proxyPort) {
                    return LsofMatch(pid: currentPid, command: currentCommand)
                }
            default:
                continue
            }
        }
        return nil
    }

    private func matchesClientToProxy(name: String, clientPort: Int, proxyPort: Int) -> Bool {
        // Example: "127.0.0.1:56321->127.0.0.1:8080"
        guard let arrowRange = name.range(of: "->") else { return false }
        let left = String(name[..<arrowRange.lowerBound])
        let right = String(name[arrowRange.upperBound...])

        let leftPort = extractPort(fromEndpoint: left)
        let rightPort = extractPort(fromEndpoint: right)
        return leftPort == clientPort && rightPort == proxyPort
    }

    private func extractPort(fromEndpoint endpoint: String) -> Int? {
        guard let colonIndex = endpoint.lastIndex(of: ":") else { return nil }
        let suffix = endpoint[endpoint.index(after: colonIndex)...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
