#if DEBUG
import Foundation

/// Test-only stdin harness for the exact client used by the composer. Not included in Release.
enum ComposerProbe {
    static func run() async {
        do {
            let bytes = FileHandle.standardInput.readDataToEndOfFile()
            guard bytes.count <= 4 * 1024 * 1024,
                  let input = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let url = input["url"] as? String else { throw ComposerTemplate.Failure.invalidRequest }
            let draft = ComposerDraft(method: input["method"] as? String ?? "GET", url: url,
                headers: ComposerHeaderRow.makeRows(from: input["headers"] as? [String: String] ?? [:]), body: input["body"] as? String ?? "", bodyIsBase64: input["bodyIsBase64"] as? Bool)
            var exactDraft = draft
            if let fields = input["headerFields"] as? [[String: String]] {
                exactDraft.headers = fields.map { .init(key: $0["name"] ?? "", value: $0["value"] ?? "") }
            }
            let request = try ComposerTemplate.request(exactDraft, variables: [])
            let certificate = (input["certificate"] as? String).flatMap { Data(base64Encoded: $0) }
            let proxyPort = input["proxyPort"] as? Int
            let execution = Task { try await ComposerHTTPClient.send(request, proxyPort: proxyPort, certificate: certificate) }
            let cancellation = (input["cancelAfterMillis"] as? Int).map { milliseconds in
                Task {
                    try await Task.sleep(for: .milliseconds(max(1, milliseconds)))
                    execution.cancel()
                }
            }
            defer { cancellation?.cancel() }
            let result = try await execution.value
            let output = try JSONSerialization.data(withJSONObject: ["status": result.status, "headers": result.headers,
                "headerFields": result.headerFields.map { ["name": $0.name, "value": $0.value] },
                "body": result.body.base64EncodedString(), "byteCount": result.byteCount])
            FileHandle.standardOutput.write(output)
        } catch {
            FileHandle.standardError.write(Data("Composer probe failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
#endif
