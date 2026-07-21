import Foundation
import Observation

@MainActor
@Observable
final class UnifiedTrafficRuleActionFormModel {
    enum Kind: String, CaseIterable, Identifiable {
        case mock
        case mapRemote
        case rewriteRequest
        case rewriteResponse
        case block
        case delay
        case breakpoint
        case script

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mock: "Mock Response"
            case .mapRemote: "Map Remote"
            case .rewriteRequest: "Rewrite Request"
            case .rewriteResponse: "Rewrite Response"
            case .block: "Block"
            case .delay: "Delay"
            case .breakpoint: "Breakpoint"
            case .script: "Script"
            }
        }
    }

    let id: UUID
    let kind: Kind
    var status: Int = 200
    var includesStatus = false
    var headersText = ""
    var body = ""
    var destinationURL = ""
    var preservePath = true
    var preserveQuery = true
    var method = ""
    var url = ""
    var includesBody = false
    var requestMilliseconds = 0
    var responseMilliseconds = 0
    var interceptRequest = true
    var interceptResponse = true
    var source = "function transform(flow) {\n  return null;\n}"
    var responseOnly = true

    init(action: TrafficRuleAction) {
        id = action.id
        switch action {
        case .mock(let value):
            kind = .mock
            status = value.status
            headersText = Self.format(headers: value.headers)
            body = value.body
        case .mapRemote(let value):
            kind = .mapRemote
            destinationURL = value.destinationURL
            preservePath = value.preservePath
            preserveQuery = value.preserveQuery
        case .rewriteRequest(let value):
            kind = .rewriteRequest
            method = value.method ?? ""
            url = value.url ?? ""
            headersText = Self.format(headers: value.headers)
            includesBody = value.body != nil
            body = value.body ?? ""
        case .rewriteResponse(let value):
            kind = .rewriteResponse
            includesStatus = value.status != nil
            status = value.status ?? 200
            headersText = Self.format(headers: value.headers)
            includesBody = value.body != nil
            body = value.body ?? ""
        case .block(let value):
            kind = .block
            status = value.status
            headersText = Self.format(headers: value.headers)
            body = value.body
        case .delay(let value):
            kind = .delay
            requestMilliseconds = value.requestMilliseconds
            responseMilliseconds = value.responseMilliseconds
        case .breakpoint(let value):
            kind = .breakpoint
            interceptRequest = value.request
            interceptResponse = value.response
        case .script(let value):
            kind = .script
            source = value.source
            responseOnly = value.responseOnly
        }
    }

    var validationMessage: String? {
        switch kind {
        case .mapRemote where URL(string: destinationURL)?.scheme == nil:
            return "Enter an absolute destination URL."
        case .delay where requestMilliseconds < 0 || responseMilliseconds < 0:
            return "Delay values cannot be negative."
        case .breakpoint where !interceptRequest && !interceptResponse:
            return "Select at least one breakpoint phase."
        case .script where source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return "Script source cannot be empty."
        default:
            return nil
        }
    }

    func makeAction() -> TrafficRuleAction {
        let headers = Self.parse(headers: headersText)
        switch kind {
        case .mock:
            return .mock(.init(id: id, status: status, headers: headers, body: body))
        case .mapRemote:
            return .mapRemote(.init(
                id: id,
                destinationURL: destinationURL,
                preservePath: preservePath,
                preserveQuery: preserveQuery
            ))
        case .rewriteRequest:
            return .rewriteRequest(.init(
                id: id,
                method: method.nilIfBlank,
                url: url.nilIfBlank,
                headers: headers,
                body: includesBody ? body : nil
            ))
        case .rewriteResponse:
            return .rewriteResponse(.init(
                id: id,
                status: includesStatus ? status : nil,
                headers: headers,
                body: includesBody ? body : nil
            ))
        case .block:
            return .block(.init(id: id, status: status, headers: headers, body: body))
        case .delay:
            return .delay(.init(
                id: id,
                requestMilliseconds: requestMilliseconds,
                responseMilliseconds: responseMilliseconds
            ))
        case .breakpoint:
            return .breakpoint(.init(id: id, request: interceptRequest, response: interceptResponse))
        case .script:
            return .script(.init(id: id, source: source, responseOnly: responseOnly))
        }
    }

    static func defaultAction(for kind: Kind) -> TrafficRuleAction {
        let id = UUID()
        switch kind {
        case .mock: return .mock(.init(id: id, status: 200, headers: [:], body: ""))
        case .mapRemote: return .mapRemote(.init(id: id, destinationURL: "https://", preservePath: true, preserveQuery: true))
        case .rewriteRequest: return .rewriteRequest(.init(id: id, method: nil, url: nil, headers: [:], body: nil))
        case .rewriteResponse: return .rewriteResponse(.init(id: id, status: nil, headers: [:], body: nil))
        case .block: return .block(.init(id: id, status: 403, headers: [:], body: "Blocked by FRTMProxy"))
        case .delay: return .delay(.init(id: id, requestMilliseconds: 0, responseMilliseconds: 250))
        case .breakpoint: return .breakpoint(.init(id: id, request: true, response: true))
        case .script: return .script(.init(id: id, source: "function transform(flow) {\n  return null;\n}", responseOnly: true))
        }
    }

    private static func format(headers: [String: String]) -> String {
        headers.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private static func parse(headers text: String) -> [String: String] {
        text.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            result[name] = value
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
