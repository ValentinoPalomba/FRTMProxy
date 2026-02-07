import Foundation

/// Best-effort process/app attribution for inbound client connections (macOS).
///
/// This is intentionally lightweight and mirrors ProxyPin's approach (lsof + ps with caching).
public actor ProcessInfoProvider {
    private struct CacheEntry {
        var createdAt: Date
        var info: ProxyProcessInfo?
    }

    private let ttl: TimeInterval = 60 * 5
    private var byPort: [Int: CacheEntry] = [:]
    private var byPID: [Int: CacheEntry] = [:]

    public init() {}

    public func processInfoForClientPort(_ port: Int) async -> ProxyProcessInfo? {
        guard port > 0 else { return nil }

        if let cached = byPort[port], Date().timeIntervalSince(cached.createdAt) < ttl {
            return cached.info
        }

        guard let pid = await getPIDForLocalPort(port) else { return nil }

        if let cached = byPID[pid], Date().timeIntervalSince(cached.createdAt) < ttl {
            byPort[port] = cached
            return cached.info
        }

        let info = await getProcessInfo(pid: pid)
        let entry = CacheEntry(createdAt: Date(), info: info)
        byPID[pid] = entry
        byPort[port] = entry

        // Best-effort: cap growth.
        if byPort.count > 50_000 { byPort.removeAll(keepingCapacity: true) }
        if byPID.count > 50_000 { byPID.removeAll(keepingCapacity: true) }
        return info
    }

    // MARK: - Internals (macOS)

    private func getPIDForLocalPort(_ port: Int) async -> Int? {
        #if os(macOS)
        let cmd = "lsof -nP -iTCP:\(port) | grep \"\(port)->\""
        guard let out = await runShell(cmd), !out.isEmpty else { return nil }

        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count >= 2, let pid = Int(parts[1]) {
                return pid
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    private func getProcessInfo(pid: Int) async -> ProxyProcessInfo? {
        #if os(macOS)
        let cmd = "ps -p \(pid) -o pid= -o comm="
        guard let out = await runShell(cmd), !out.isEmpty else { return nil }

        // Expected: "<pid> <comm...>"
        let lines = out.split(separator: "\n")
        for line in lines {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }

            var rest = parts
            _ = rest.removeFirst() // pid
            let comm = rest.joined(separator: " ")

            // Best-effort: derive ".app" path like ProxyPin.
            let base = comm.components(separatedBy: ".app/").first ?? comm
            let appPath = base.hasSuffix(".app") ? base : (base + ".app")

            let name = URL(fileURLWithPath: base).lastPathComponent
            return ProxyProcessInfo(id: name, name: name, path: appPath)
        }
        return nil
        #else
        return nil
        #endif
    }

    private func runShell(_ command: String) async -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", command]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(decoding: data, as: UTF8.self)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
