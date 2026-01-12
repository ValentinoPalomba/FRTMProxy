import Combine
import Foundation
import SwiftUI

struct MapEditorPayload {
    let requestBody: String?
    let requestHeaders: [String: String]
    let responseBody: String
    let responseStatus: Int
    let responseHeaders: [String: String]
}

struct MapEditorRetryPayload {
    let flowID: String
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?
}

final class MapEditorViewModel: ObservableObject {
    @Published var requestBody: String = ""
    @Published var responseBody: String = ""
    @Published var responseStatusText: String = "200"
    @Published var requestMethod: String = ""
    @Published var requestUrl: String = ""

    @Published var requestHeaders: [MapEditorKeyValueRow] = []
    @Published var responseHeaders: [MapEditorKeyValueRow] = []
    @Published var queryParameters: [MapEditorKeyValueRow] = []

    @Published private(set) var title: String = ""
    @Published private(set) var isModified: Bool = false
    @Published private(set) var hasSelection: Bool = false

    private var snapshot: Snapshot?
    private var isApplyingSnapshot = false
    private var cancellables: Set<AnyCancellable> = []
    private var currentFlowID: String?

    init() {
        bindDirtyTracking()
    }

    func load(flow: MitmFlow) {
        currentFlowID = flow.id
        let status = flow.response?.status.map(String.init) ?? "200"
        let requestHeaderRows = MapEditorKeyValueRow.makeRows(from: flow.request?.headers ?? [:])
        let responseHeaderRows = MapEditorKeyValueRow.makeRows(from: flow.response?.headers ?? [:])
        let queryRows = MapEditorKeyValueRow.makeRows(from: URLComponents(string: flow.request?.url ?? "")?.queryItems ?? [])
        let title = "\(flow.request?.method ?? "") \(flow.path)"

        let snap = Snapshot(
            requestBody: FormattingUtils.formattedBodyForEdit(flow.request?.body),
            requestHeaders: requestHeaderRows,
            responseBody: FormattingUtils.formattedBodyForEdit(flow.response?.body),
            responseHeaders: responseHeaderRows,
            responseStatusText: status,
            queryParameters: queryRows,
            title: title,
            requestMethod: flow.request?.method ?? "",
            requestUrl: flow.request?.url ?? ""
        )
        apply(snapshot: snap)
    }

    func load(rule: MapRule) {
        currentFlowID = nil
        let snap = Snapshot(
            requestBody: "",
            requestHeaders: [],
            responseBody: FormattingUtils.formattedBodyForEdit(rule.body),
            responseHeaders: MapEditorKeyValueRow.makeRows(from: rule.headers),
            responseStatusText: String(rule.status),
            queryParameters: [],
            title: "\(rule.host)\(rule.path)",
            requestMethod: "",
            requestUrl: ""
        )
        apply(snapshot: snap)
    }

    func clear() {
        snapshot = nil
        title = ""
        hasSelection = false
        isModified = false
        requestBody = ""
        responseBody = ""
        responseStatusText = "200"
        requestHeaders = []
        responseHeaders = []
        queryParameters = []
        requestMethod = ""
        requestUrl = ""
        currentFlowID = nil
    }

    func revert() {
        guard let snapshot else { return }
        apply(snapshot: snapshot)
    }

    func markSynced() {
        snapshot = currentSnapshot()
        isModified = false
    }

    func payload(defaultStatus: Int) -> MapEditorPayload? {
        guard hasSelection else { return nil }
        let responseStatus = Int(responseStatusText) ?? defaultStatus
        return MapEditorPayload(
            requestBody: requestBody.isEmpty ? nil : requestBody,
            requestHeaders: headersDictionary(from: requestHeaders),
            responseBody: responseBody,
            responseStatus: responseStatus,
            responseHeaders: headersDictionary(from: responseHeaders)
        )
    }

    func retryPayload() -> MapEditorRetryPayload? {
        guard hasSelection, let flowID = currentFlowID else { return nil }
        let headers = headersDictionary(from: requestHeaders)
        let method = requestMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        var targetURL = requestUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        if var components = URLComponents(string: targetURL), let items = normalizedQueryItems() {
            components.queryItems = items
            targetURL = components.string ?? targetURL
        }

        guard !targetURL.isEmpty else { return nil }

        return MapEditorRetryPayload(
            flowID: flowID,
            method: method.isEmpty ? flowRequestMethodFallback : method.uppercased(),
            url: targetURL,
            headers: headers,
            body: requestBody.isEmpty ? nil : requestBody
        )
    }

    func addRequestHeader() {
        requestHeaders.append(.empty())
    }

    func removeRequestHeader(id: UUID) {
        requestHeaders.removeAll { $0.id == id }
    }

    func addResponseHeader() {
        responseHeaders.append(.empty())
    }

    func removeResponseHeader(id: UUID) {
        responseHeaders.removeAll { $0.id == id }
    }

    func addQueryParameter() {
        queryParameters.append(.empty())
    }

    func removeQueryParameter(id: UUID) {
        queryParameters.removeAll { $0.id == id }
    }

    private func normalizedQueryItems() -> [URLQueryItem]? {
        let items = queryParameters.compactMap { row -> URLQueryItem? in
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return URLQueryItem(name: key, value: row.value)
        }
        return items.isEmpty ? nil : items
    }

    private var flowRequestMethodFallback: String {
        let stored = snapshot?.requestMethod.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "GET" : stored.uppercased()
    }

    private func apply(snapshot: Snapshot) {
        isApplyingSnapshot = true
        requestBody = snapshot.requestBody
        requestHeaders = snapshot.requestHeaders
        responseBody = snapshot.responseBody
        responseHeaders = snapshot.responseHeaders
        responseStatusText = snapshot.responseStatusText
        queryParameters = snapshot.queryParameters
        title = snapshot.title
        requestMethod = snapshot.requestMethod
        requestUrl = snapshot.requestUrl
        snapshotStore(snapshot)
        isApplyingSnapshot = false
        isModified = false
        hasSelection = true
    }

    private func headersDictionary(from rows: [MapEditorKeyValueRow]) -> [String: String] {
        rows.reduce(into: [String: String]()) { result, row in
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = row.value
        }
    }

    private func snapshotStore(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    private func currentSnapshot() -> Snapshot? {
        guard hasSelection else { return nil }
        return Snapshot(
            requestBody: requestBody,
            requestHeaders: requestHeaders,
            responseBody: responseBody,
            responseHeaders: responseHeaders,
            responseStatusText: responseStatusText,
            queryParameters: queryParameters,
            title: title,
            requestMethod: requestMethod,
            requestUrl: requestUrl
        )
    }

    private func bindDirtyTracking() {
        func publisher<T>(_ published: Published<T>.Publisher) -> AnyPublisher<Void, Never> {
            published.dropFirst().map { _ in () }.eraseToAnyPublisher()
        }

        Publishers.MergeMany(
            publisher($requestBody),
            publisher($responseBody),
            publisher($responseStatusText),
            publisher($requestHeaders),
            publisher($responseHeaders),
            publisher($queryParameters),
            publisher($requestMethod),
            publisher($requestUrl)
        )
        .sink { [weak self] _ in
            guard let self else { return }
            guard !isApplyingSnapshot, snapshot != nil else { return }
            self.isModified = true
        }
        .store(in: &cancellables)
    }
}

struct MapEditorKeyValueRow: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }

    static func makeRows(from headers: [String: String]) -> [MapEditorKeyValueRow] {
        headers
            .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
            .map { MapEditorKeyValueRow(key: $0.key, value: $0.value) }
    }

    static func makeRows(from queryItems: [URLQueryItem]) -> [MapEditorKeyValueRow] {
        queryItems
            .map { MapEditorKeyValueRow(key: $0.name, value: $0.value ?? "") }
    }

    static func empty() -> MapEditorKeyValueRow {
        MapEditorKeyValueRow(key: "", value: "")
    }
}

private struct Snapshot: Equatable {
    let requestBody: String
    let requestHeaders: [MapEditorKeyValueRow]
    let responseBody: String
    let responseHeaders: [MapEditorKeyValueRow]
    let responseStatusText: String
    let queryParameters: [MapEditorKeyValueRow]
    let title: String
    let requestMethod: String
    let requestUrl: String
}
