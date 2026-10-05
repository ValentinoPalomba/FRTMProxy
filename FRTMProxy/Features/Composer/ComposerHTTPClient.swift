import Foundation

/// Owns one curl process; arguments are passed directly, with no shell or trust bypass.
final class ComposerHTTPClient: @unchecked Sendable {
    struct Result: Sendable {
        let status: Int
        let headers: [String: String]
        let headerFields: [HTTPHeaderField]
        let body: Data
        let byteCount: Int
    }
    private struct Preview: Sendable { let bytes: Data; let count: Int }
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    private func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        self.process = process
        try process.run()
    }
    private func cancel() {
        lock.lock()
        cancelled = true
        let owned = process
        lock.unlock()
        if owned?.isRunning == true { owned?.terminate() }
    }
    private static func read(_ handle: FileHandle, limit: Int) throws -> Preview {
        var preview = Data()
        var count = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            count += chunk.count
            preview.append(chunk.prefix(max(0, limit - preview.count)))
        }
        return Preview(bytes: preview, count: count)
    }

    static func send(_ request: ComposerTemplate.Request, proxyPort: Int?, certificate: Data? = nil) async throws -> Result {
        let owner = ComposerHTTPClient()
        return try await withTaskCancellationHandler {
            try await owner.execute(request, proxyPort: proxyPort, certificate: certificate)
        } onCancel: { owner.cancel() }
    }

    private func execute(_ request: ComposerTemplate.Request, proxyPort: Int?, certificate: Data?) async throws -> Result {
        let url = request.url
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ComposerTemplate.Failure.invalidRequest
        }
        var args = ["--disable", "--globoff", "--path-as-is", "--silent", "--show-error",
                    "--connect-timeout", "10", "--max-time", "60", "--proto", "=http,https",
                    "--proto-redir", "=http,https", "--dump-header", "/dev/stderr", "--request", request.method]
        let certificateDirectory: URL?
        if let proxyPort {
            guard (1024...65535).contains(proxyPort) else { throw ComposerTemplate.Failure.invalidRequest }
            args += ["--proxy", "http://127.0.0.1:\(proxyPort)", "--noproxy", ""]
            let caURL: URL
            if let certificate {
                let directory = FileManager.default.temporaryDirectory.appending(path: "frtm-composer-ca-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                certificateDirectory = directory
                caURL = directory.appending(path: "ca.pem")
                let pem = "-----BEGIN CERTIFICATE-----\n" + certificate.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END CERTIFICATE-----\n"
                try Data(pem.utf8).write(to: caURL, options: .atomic)
            } else {
                certificateDirectory = nil
                caURL = try MitmproxyCertificateLoader().pemURL()
            }
            args += ["--cacert", caURL.path]
        } else {
            certificateDirectory = nil
            args += ["--proxy", ""]
        }
        defer { if let certificateDirectory { try? FileManager.default.removeItem(at: certificateDirectory) } }
        for field in request.headers {
            args += ["--header", field.value.isEmpty ? "\(field.name);" : "\(field.name): \(field.value)"]
        }
        if request.body != nil, !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) {
            args += ["--header", "Content-Type:"]
        }
        if request.body != nil { args += ["--data-binary", "@-"] }
        args += ["--url", request.transportURL]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args
        let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try start(process)
        let bodyReader = Task.detached { try Self.read(stdout.fileHandleForReading, limit: 2 * 1024 * 1024) }
        let headerReader = Task.detached { try Self.read(stderr.fileHandleForReading, limit: 128 * 1024) }
        let writer = Task.detached {
            defer { try? stdin.fileHandleForWriting.close() }
            if let body = request.body { try stdin.fileHandleForWriting.write(contentsOf: body) }
        }
        do {
            try await writer.value
            let body = try await bodyReader.value
            let header = try await headerReader.value
            process.waitUntilExit()
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                let text = String(decoding: header.bytes, as: UTF8.self)
                let diagnostic = text.components(separatedBy: .newlines).last(where: { $0.hasPrefix("curl:") }) ?? "curl failed (\(process.terminationStatus))"
                throw NSError(domain: "curl", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: diagnostic])
            }
            guard header.count == header.bytes.count else { throw CocoaError(.fileReadTooLarge) }
            let lines = String(decoding: header.bytes, as: UTF8.self).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
            guard let start = lines.lastIndex(where: { $0.hasPrefix("HTTP/") }),
                  let status = Int(lines[start].split(separator: " ").dropFirst().first ?? ""), (100...599).contains(status) else {
                throw URLError(.badServerResponse)
            }
            var fields: [HTTPHeaderField] = []
            for line in lines.dropFirst(start + 1) {
                if line.isEmpty { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields.append(.init(name: String(line[..<colon]), value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            }
            return Result(status: status, headers: fields.reduce(into: [:]) { $0[$1.name] = $1.value },
                          headerFields: fields, body: body.bytes, byteCount: body.count)
        } catch {
            cancel()
            _ = try? await writer.value
            _ = try? await bodyReader.value
            _ = try? await headerReader.value
            if process.isRunning { process.waitUntilExit() }
            throw error
        }
    }
}
