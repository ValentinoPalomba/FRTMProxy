import Foundation
import Combine

// MARK: - RequestComposerViewModel

@MainActor
final class RequestComposerViewModel: ObservableObject {
    @Published var method: String = "GET"
    @Published var urlString: String = ""
    @Published var requestHeaders: [ComposerHeaderRow] = []
    @Published var requestBody: String = ""

    @Published var isLoading: Bool = false
    @Published var responseStatus: Int?
    @Published var responseHeaders: [String: String] = [:]
    @Published var responseBody: String?
    @Published var errorMessage: String?

    static let httpMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    // MARK: - Send

    func send(proxyPort: Int?) async {
        let rawURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil
        responseStatus = nil
        responseBody = nil
        responseHeaders = [:]

        do {
            let output = try await runCurl(url: rawURL, proxyPort: proxyPort)
            parseResponse(output)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - curl execution

    /// Runs curl in a background task and returns its raw stdout (headers + body).
    /// Uses `-s -i -L` so we get status line + headers + body in one stream.
    /// When proxyPort is provided, routes traffic through mitmproxy with `--proxy-insecure`
    /// so the MITM certificate is accepted without errors.
    private func runCurl(url: String, proxyPort: Int?) async throws -> String {
        // Capture @MainActor state before going off-thread
        let capturedMethod   = method
        let capturedHeaders  = requestHeaders
        let capturedBody     = requestBody
        let hasBody          = !requestBody.isEmpty && method != "GET" && method != "HEAD"

        return try await Task.detached(priority: .userInitiated) {
            var args: [String] = [
                "-s",           // silent (no progress meter)
                "-i",           // include response headers in output
                "-L",           // follow redirects
                "-X", capturedMethod
            ]

            // Request headers
            for row in capturedHeaders {
                let k = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    args += ["-H", "\(k): \(v)"]
                }
            }

            // Proxy — --proxy-insecure accepts the mitmproxy MITM certificate
            if let port = proxyPort {
                args += ["-x", "http://127.0.0.1:\(port)", "--proxy-insecure"]
            }

            // Body via stdin so we avoid shell-escaping issues
            if hasBody {
                args += ["--data-binary", "@-"]
            }

            args.append(url)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            if hasBody {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                try process.run()
                if let bodyData = capturedBody.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(bodyData)
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } else {
                try process.run()
            }

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "curl exited with code \(process.terminationStatus)"
                throw NSError(
                    domain: "curl",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errMsg]
                )
            }

            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    // MARK: - Response parsing

    /// Parses the raw curl output (status line + headers + body) into view-model state.
    ///
    /// When following redirects curl emits multiple HTTP header blocks separated by
    /// blank lines. We find the *last* block that starts with "HTTP/" and treat
    /// everything after the subsequent blank line as the body.
    private func parseResponse(_ raw: String) {
        // Determine line endings
        let useCRLF    = raw.contains("\r\n\r\n")
        let blockSep   = useCRLF ? "\r\n\r\n" : "\n\n"
        let lineSep    = useCRLF ? "\r\n"     : "\n"

        // Split into blocks. The final element after the last separator is the body.
        var blocks: [String] = []
        var remaining = raw
        while let range = remaining.range(of: blockSep) {
            blocks.append(String(remaining[remaining.startIndex..<range.lowerBound]))
            remaining = String(remaining[range.upperBound...])
        }
        // `remaining` is now the body
        let bodyText = remaining

        // Find the last HTTP header block (handles 100-Continue, redirects, etc.)
        let lastHeaderBlock = blocks.reversed().first { block in
            let trimmed = block.trimmingCharacters(in: .init(charactersIn: "\r\n"))
            return trimmed.hasPrefix("HTTP/")
        }

        guard let headerBlock = lastHeaderBlock else {
            // No recognisable HTTP header — just store raw output
            responseBody = raw
            return
        }

        let headerLines = headerBlock.components(separatedBy: lineSep)

        // Status line: "HTTP/1.1 200 OK" or "HTTP/2 200"
        if let statusLine = headerLines.first {
            let parts = statusLine.components(separatedBy: " ")
            if parts.count >= 2, let code = Int(parts[1]) {
                responseStatus = code
            }
        }

        // Header fields (skip the status line)
        var parsedHeaders: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key   = String(line[line.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                parsedHeaders[key] = value
            }
        }
        responseHeaders = parsedHeaders
        responseBody    = bodyText
    }

    // MARK: - Helpers

    func loadFromFlow(_ flow: MitmFlow) {
        urlString     = flow.request?.url ?? ""
        method        = flow.request?.method ?? "GET"
        requestHeaders = ComposerHeaderRow.makeRows(from: flow.request?.headers ?? [:])
        requestBody   = flow.request?.body ?? ""
        responseStatus  = nil
        responseBody    = nil
        responseHeaders = [:]
        errorMessage    = nil
    }

    func addHeaderRow() {
        requestHeaders.append(ComposerHeaderRow(key: "", value: ""))
    }

    func removeHeaderRow(at offsets: IndexSet) {
        requestHeaders.remove(atOffsets: offsets)
    }
}

// MARK: - ComposerHeaderRow

struct ComposerHeaderRow: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }

    static func makeRows(from headers: [String: String]) -> [ComposerHeaderRow] {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { ComposerHeaderRow(key: $0.key, value: $0.value) }
    }
}
