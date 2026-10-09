import AppKit
import Foundation
import UniformTypeIdentifiers

enum SessionHARExporter {
    /// Uses recorded protocol, timing and repeated headers. Redacted exports omit bodies by default.
    static func data(flows: [MitmFlow], redacted: Bool = true) throws -> Data {
        let entries: [[String: Any]] = try flows.map { flow in
            guard let request = flow.request,
                  let start = flow.requestTimestamp ?? flow.timestamp else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let response = flow.response ?? MitmFlow.Response(status: 0, headers: [:], body: nil)
            let safeRequest = try AutomationRedactor.redact(.init(url: request.url, headers: request.headers, body: request.body))
            let url = redacted ? safeRequest.url ?? "" : request.url
            let requestBody = try body(preview: request.body, reference: request.originalBodyReference,
                                       truncated: request.bodyTruncated ?? false, flowID: flow.id, phase: "request", redacted: redacted)
            let responseBody = try body(preview: response.body, reference: response.originalBodyReference,
                                        truncated: response.bodyTruncated ?? false, flowID: flow.id, phase: "response", redacted: redacted)
            var requestObject: [String: Any] = [
                "method": request.method, "url": url, "httpVersion": request.httpVersion ?? "",
                "headers": headers(request.headerFields, fallback: request.headers, redacted: redacted),
                "queryString": (URLComponents(string: url)?.queryItems ?? []).map { ["name": $0.name, "value": $0.value ?? ""] },
                "cookies": [], "headersSize": -1, "bodySize": request.byteCount ?? -1
            ]
            if let requestBody {
                requestObject["postData"] = ["mimeType": mime(request.headers), "text": requestBody.base64EncodedString(), "_encoding": "base64"]
            }
            var content: [String: Any] = ["size": response.byteCount ?? -1, "mimeType": mime(response.headers ?? [:])]
            if let responseBody {
                content["text"] = responseBody.base64EncodedString()
                content["encoding"] = "base64"
            }
            let milliseconds = flow.duration.map { $0 * 1000 }
            var entry: [String: Any] = [
                "startedDateTime": Date(timeIntervalSince1970: start).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
                "request": requestObject,
                "response": ["status": response.status ?? 0, "statusText": "", "httpVersion": response.httpVersion ?? "",
                             "headers": headers(response.headerFields, fallback: response.headers ?? [:], redacted: redacted),
                             "cookies": [], "content": content, "redirectURL": "", "headersSize": -1, "bodySize": response.byteCount ?? -1],
                "time": milliseconds ?? -1,
                "timings": ["send": -1, "wait": -1, "receive": -1],
                "_captureEvent": flow.event, "_bodiesOmitted": redacted,
                "_previewTruncated": (request.bodyTruncated ?? false) || (response.bodyTruncated ?? false)
            ]
            // Unknown DNS/connect/TLS phases remain unknown; elapsed total is recorded separately.
            if let milliseconds { entry["time"] = milliseconds }
            if let captureError = flow.captureError { entry["_captureError"] = captureError }
            return entry
        }
        return try JSONSerialization.data(withJSONObject: ["log": ["version": "1.2", "creator": ["name": "FRTMProxy", "version": "1.8.1"], "entries": entries]],
                                          options: [.prettyPrinted, .sortedKeys])
    }

    /// Pages the entire closed session; memory is bounded to a page and one entry.
    static func writeSession(_ session: CaptureSession, to destination: URL, redacted: Bool,
                             loadPage: SessionBrowserView.LoadPage) async throws {
        guard !session.isActive else { throw CocoaError(.featureUnsupported) }
        let temporary = destination.deletingLastPathComponent().appending(path: ".frtm-har-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(#"{"log":{"version":"1.2","creator":{"name":"FRTMProxy","version":"1.8.1"},"entries":["#.utf8))
        var cursor: CaptureSessionPageCursor?
        var count = 0
        repeat {
            try Task.checkCancellation()
            let page = try await loadPage(session.id, cursor, 200)
            guard page.corruptFlowIDs.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            for item in page.flows {
                let serialized = try data(flows: [item.flow], redacted: redacted)
                let document = try JSONSerialization.jsonObject(with: serialized) as? [String: Any]
                let log = document?["log"] as? [String: Any]
                guard let entry = (log?["entries"] as? [[String: Any]])?.first else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if count > 0 { try handle.write(contentsOf: Data(",".utf8)) }
                try handle.write(contentsOf: JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]))
                count += 1
            }
            if let next = page.nextCursor, next == cursor { throw CocoaError(.fileReadCorruptFile) }
            cursor = page.nextCursor
        } while cursor != nil
        guard count == session.flowCount else { throw CocoaError(.fileReadCorruptFile) }
        try handle.write(contentsOf: Data("]}}".utf8))
        try handle.synchronize()
        try handle.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    @MainActor
    static func export(session: CaptureSession, redacted: Bool, loadPage: @escaping SessionBrowserView.LoadPage) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = redacted ? "session-redacted.har" : "session.har"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do { try await writeSession(session, to: destination, redacted: redacted, loadPage: loadPage) }
            catch {
                let alert = NSAlert()
                alert.messageText = "Unable to export session"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private static func body(preview: String?, reference: String?, truncated: Bool, flowID: String, phase: String, redacted: Bool) throws -> Data? {
        if redacted { return nil }
        if let reference { return try CaptureBodyStore.load(reference: reference, flowID: flowID, phase: phase) }
        guard !truncated else { throw CocoaError(.fileReadTooLarge) }
        guard let preview else { return nil }
        if preview.hasPrefix("data:"), let comma = preview.firstIndex(of: ","), preview[..<comma].hasSuffix(";base64") {
            return Data(base64Encoded: String(preview[preview.index(after: comma)...]))
        }
        return Data(preview.utf8)
    }

    private static func headers(_ fields: [HTTPHeaderField]?, fallback: [String: String], redacted: Bool) -> [[String: String]] {
        let values = fields ?? fallback.sorted(by: { $0.key < $1.key }).map { HTTPHeaderField(name: $0.key, value: $0.value) }
        return values.map { field in
            ["name": field.name, "value": redacted && RedactionPolicy.defaults.matchesSensitiveHeader(field.name) ? "[REDACTED]" : field.value]
        }
    }

    private static func mime(_ headers: [String: String]) -> String {
        headers.first(where: { $0.key.caseInsensitiveCompare("content-type") == .orderedSame })?.value ?? "application/octet-stream"
    }

    @MainActor
    static func export(flows: [MitmFlow], redacted: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = redacted ? "capture-redacted.har" : "capture.har"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try data(flows: flows, redacted: redacted).write(to: destination, options: .atomic)
                }.value
            } catch {
                let alert = NSAlert()
                alert.messageText = "Unable to export HAR"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
