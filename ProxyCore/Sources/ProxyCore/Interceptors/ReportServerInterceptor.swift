import Foundation

/// ProxyPin-style report server delivery (`report_servers.json`).
public struct ReportServerInterceptor: ProxyInterceptor {
    public typealias Logger = @Sendable (String) -> Void

    public let store: ReportServerStore
    public let logger: Logger

    public init(store: ReportServerStore, logger: @escaping Logger = { _ in }) {
        self.store = store
        self.logger = logger
    }

    public var priority: Int { 1000 }

    public func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        Task.detached { [store, logger, request, response] in
            await Self.report(store: store, logger: logger, request: request, response: response)
        }
        return response
    }

    public func onError(request: ProxyRequest?, error: any Error) async {
        guard let request else { return }
        Task.detached { [store, logger, request] in
            await Self.report(store: store, logger: logger, request: request, response: nil)
        }
    }

    private static func report(store: ReportServerStore, logger: Logger, request: ProxyRequest, response: ProxyResponse?) async {
        guard let server = await store.matchServer(url: request.url) else { return }

        var serverUrl = server.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if serverUrl.isEmpty {
            return
        }
        if !serverUrl.lowercased().hasPrefix("http://") && !serverUrl.lowercased().hasPrefix("https://") {
            serverUrl = "http://" + serverUrl
        }
        guard let url = URL(string: serverUrl) else { return }

        let entry = ReportHarEntry.make(request: request, response: response)
        let encoder = JSONEncoder()
        let json: Data
        do {
            json = try encoder.encode(entry)
        } catch {
            return
        }

        var body = json
        let compression = server.compression?.lowercased() ?? "none"
        if compression == "gzip" {
            do {
                body = try Gzip.compress(body)
            } catch {
                // Best-effort: send uncompressed if compression fails.
                body = json
            }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if !server.name.isEmpty {
            req.setValue(server.name, forHTTPHeaderField: "X-Report-Name")
        }
        if compression == "gzip" {
            req.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        }
        req.httpBody = body

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status < 200 || status >= 300 {
                logger("[ProxyCore] reportServer delivery failed: status=\(status) url=\(url)\n")
            }
        } catch {
            logger("[ProxyCore] reportServer delivery error: \(error)\n")
        }
    }
}

