import Foundation
import Combine

@MainActor
final class RequestComposerViewModel: ObservableObject {
    @Published var method = "GET"
    @Published var urlString = ""
    @Published var requestHeaders: [ComposerHeaderRow] = []
    @Published var requestBody = ""
    @Published var bodyIsBase64 = false
    @Published var showsRequestHeaders = false
    @Published private(set) var history: [ComposerDraft] = []
    @Published var variables: [ComposerHeaderRow] = []
    @Published private(set) var isRestoring = true
    @Published var isLoading = false
    @Published var responseStatus: Int?
    @Published var responseHeaders: [String: String] = [:]
    @Published private(set) var responseHeaderFields: [HTTPHeaderField] = []
    @Published var responseBody: String?
    @Published private(set) var responseByteCount = 0
    @Published private(set) var responseTruncated = false
    @Published var errorMessage: String?
    @Published private(set) var persistenceError: String?
    private let store: ComposerStateStore
    private var execution: Task<ComposerHTTPClient.Result, Error>?
    private var generation = UUID()
    private var isLoadingOriginal = false
    @Published private(set) var restoreFailed = false
    private var persistenceRevision = UUID()
    static let httpMethods = ComposerTemplate.httpMethods

    init(store: ComposerStateStore = ComposerStateStore()) {
        self.store = store
        Task { [weak self] in
            do {
                let state = try await store.load()
                self?.history = state.history
                self?.variables = state.variables
            } catch {
                self?.persistenceError = error.localizedDescription
                self?.restoreFailed = true
            }
            self?.isRestoring = false
        }
    }

    func send(proxyPort: Int?) async {
        guard !isLoading, !isRestoring else { return }
        let draft = ComposerDraft(method: method, url: urlString, headers: requestHeaders, body: requestBody, bodyIsBase64: bodyIsBase64)
        let request: ComposerTemplate.Request
        do { request = try ComposerTemplate.request(draft, variables: variables) }
        catch { errorMessage = error.localizedDescription; return }
        let id = UUID()
        generation = id
        isLoading = true
        errorMessage = nil
        responseStatus = nil
        responseBody = nil
        responseHeaders = [:]
        responseHeaderFields = []
        responseByteCount = 0
        responseTruncated = false
        let task = Task { try await ComposerHTTPClient.send(request, proxyPort: proxyPort) }
        execution = task
        do {
            let output = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard generation == id else { return }
            responseStatus = output.status
            responseHeaders = output.headers
            responseHeaderFields = output.headerFields
            responseByteCount = output.byteCount
            responseTruncated = output.byteCount > output.body.count
            responseBody = String(data: output.body, encoding: .utf8) ?? "data:application/octet-stream;base64," + output.body.base64EncodedString()
        } catch {
            guard generation == id else { return }
            errorMessage = error.localizedDescription
        }
        guard generation == id else { return }
        isLoading = false
        execution = nil
        history.insert(draft, at: 0)
        await saveLocalState()
    }

    func cancel() {
        if isLoadingOriginal { urlString = "" }
        isLoadingOriginal = false
        generation = UUID()
        execution?.cancel()
        execution = nil
        isLoading = false
    }

    func saveLocalState() async {
        guard !isRestoring, !restoreFailed else { return }
        let revision = UUID()
        persistenceRevision = revision
        do {
            let saved = try await store.save(.init(history: history, variables: variables))
            guard persistenceRevision == revision else { return }
            history = saved.history
            persistenceError = nil
        } catch {
            guard persistenceRevision == revision else { return }
            persistenceError = error.localizedDescription
        }
    }

    func resetLocalState() async {
        do {
            try await store.resetPreservingBackup()
            history = []
            variables = []
            restoreFailed = false
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    func saveVariables(_ rows: [ComposerHeaderRow]) async throws {
        guard !isRestoring, !restoreFailed else { throw CocoaError(.fileReadUnknown) }
        _ = try ComposerTemplate.request(.init(method: "GET", url: "https://example.com", headers: [], body: ""), variables: rows)
        let saved = try await store.save(.init(history: history, variables: rows))
        variables = saved.variables
        history = saved.history
        persistenceError = nil
    }

    func clearHistory() async {
        history = []
        await saveLocalState()
    }

    func loadDraft(_ draft: ComposerDraft) {
        cancel()
        urlString = draft.url
        method = draft.method
        requestHeaders = draft.headers
        requestBody = draft.body
        bodyIsBase64 = draft.bodyIsBase64 ?? false
        responseStatus = nil
        responseBody = nil
        responseHeaders = [:]
        responseHeaderFields = []
        responseByteCount = 0
        responseTruncated = false
        errorMessage = nil
    }

    func loadFromFlow(_ flow: MitmFlow) async {
        loadDraft(.init(method: flow.request?.method ?? "GET", url: flow.request?.url ?? "", headers: [], body: ""))
        isLoading = true
        isLoadingOriginal = true
        let id = generation
        do {
            guard let source = flow.request else { throw ComposerTemplate.Failure.invalidRequest }
            let bytes: Data
            if let reference = source.originalBodyReference {
                let flowID = flow.id
                bytes = try await Task.detached {
                    try CaptureBodyStore.load(reference: reference, flowID: flowID, phase: "request", maximumBytes: 2 * 1024 * 1024)
                }.value
            } else {
                guard source.bodyTruncated != true,
                      !source.headers.keys.contains(where: { $0.lowercased() == "content-encoding" }) else {
                    throw ComposerTemplate.Failure.invalidRequest
                }
                let preview = source.body ?? ""
                if preview.hasPrefix("data:"), let comma = preview.firstIndex(of: ","),
                   preview[..<comma].hasSuffix(";base64"), let decoded = Data(base64Encoded: String(preview[preview.index(after: comma)...])) {
                    bytes = decoded
                } else { bytes = Data(preview.utf8) }
                if let byteCount = source.byteCount, byteCount != bytes.count {
                    throw ComposerTemplate.Failure.invalidRequest
                }
            }
            guard bytes.count <= 2 * 1024 * 1024 else { throw ComposerTemplate.Failure.invalidRequest }
            let rows = source.headerFields?.map { ComposerHeaderRow(key: $0.name, value: $0.value) }
                ?? ComposerHeaderRow.makeRows(from: source.headers)
            guard generation == id else { return }
            let compressed = rows.contains { $0.key.lowercased() == "content-encoding" }
            let text = compressed ? nil : String(data: bytes, encoding: .utf8)
            loadDraft(.init(method: source.method, url: source.url, headers: rows,
                            body: text ?? bytes.base64EncodedString(), bodyIsBase64: text == nil))
        } catch {
            guard generation == id else { return }
            urlString = ""
            isLoadingOriginal = false
            errorMessage = "Cannot replay the original request: " + error.localizedDescription
        }
        if generation == id { isLoading = false }
    }
    @discardableResult
    func addHeaderRow() -> UUID? {
        guard requestHeaders.count < 128 else {
            errorMessage = ComposerTemplate.Failure.headerLimit.localizedDescription
            return nil
        }
        let row = ComposerHeaderRow(key: "", value: "")
        requestHeaders.append(row)
        return row.id
    }
    func removeHeaderRow(at offsets: IndexSet) { requestHeaders.remove(atOffsets: offsets) }
}
