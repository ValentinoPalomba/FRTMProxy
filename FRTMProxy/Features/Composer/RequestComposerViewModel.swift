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

    func send(proxyPort: Int?) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil
        responseStatus = nil
        responseBody = nil
        responseHeaders = [:]

        var request = URLRequest(url: url)
        request.httpMethod = method
        requestHeaders.forEach { row in
            let k = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let v = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { request.setValue(v, forHTTPHeaderField: k) }
        }
        if method != "GET", method != "HEAD", !requestBody.isEmpty {
            request.httpBody = requestBody.data(using: .utf8)
        }

        let config = URLSessionConfiguration.ephemeral
        if let port = proxyPort {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPProxy: "127.0.0.1",
                kCFNetworkProxiesHTTPPort: port,
                kCFNetworkProxiesHTTPSEnable: true,
                kCFNetworkProxiesHTTPSProxy: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort: port
            ] as [AnyHashable: Any]
        }

        do {
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                responseStatus = httpResponse.statusCode
                var headers: [String: String] = [:]
                for (k, v) in httpResponse.allHeaderFields {
                    if let key = k as? String, let val = v as? String {
                        headers[key] = val
                    }
                }
                responseHeaders = headers
            }
            if let text = String(data: data, encoding: .utf8) {
                responseBody = text
            } else {
                responseBody = "<binary data, \(data.count) bytes>"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadFromFlow(_ flow: MitmFlow) {
        urlString = flow.request?.url ?? ""
        method = flow.request?.method ?? "GET"
        requestHeaders = ComposerHeaderRow.makeRows(from: flow.request?.headers ?? [:])
        requestBody = flow.request?.body ?? ""
        responseStatus = nil
        responseBody = nil
        responseHeaders = [:]
        errorMessage = nil
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
