import Foundation
import JavaScriptCore

extension ProxyViewModel {

    // MARK: - Persistence

    func loadPersistedScripts() {
        scripts = scriptStore.load()
    }

    func persistScripts() {
        scriptStore.save(scripts)
    }

    // MARK: - Execution

    /// Run all enabled matching scripts against `flow` after a response event.
    func processScripts(for flow: MitmFlow) {
        guard flow.response != nil else { return }

        let matchingScripts = scripts.filter { rule in
            guard rule.isEnabled else { return false }
            let hostMatch = rule.host.isEmpty || flow.host.lowercased().contains(rule.host.lowercased())
            let pathMatch = rule.path.isEmpty || flow.path.hasPrefix(rule.path)
            return hostMatch && pathMatch
        }

        for rule in matchingScripts {
            if let result = executeScript(rule, for: flow) {
                service.mockResponse(
                    for: flow.id,
                    body: result.body,
                    status: result.status,
                    headers: result.headers
                )
                appendLog("[SCRIPT] \"\(rule.name)\" applied to \(flow.host)\(flow.path)\n")
            }
        }
    }

    // MARK: - Private helpers

    private struct ScriptResult {
        let status: Int
        let headers: [String: String]
        let body: String
    }

    private func executeScript(_ rule: ScriptRule, for flow: MitmFlow) -> ScriptResult? {
        guard let context = JSContext() else { return nil }

        context.exceptionHandler = { [weak self] _, exception in
            let msg = exception?.toString() ?? "unknown error"
            self?.appendLog("[SCRIPT ERROR] \"\(rule.name)\": \(msg)\n")
        }

        let requestDict: [String: Any] = [
            "url": flow.request?.url ?? "",
            "method": flow.request?.method ?? "",
            "headers": flow.request?.headers ?? [:],
            "body": flow.request?.body ?? ""
        ]
        let responseDict: [String: Any] = [
            "status": flow.response?.status ?? 200,
            "headers": flow.response?.headers ?? [:],
            "body": flow.response?.body ?? ""
        ]
        let flowDict: [String: Any] = ["request": requestDict, "response": responseDict]

        guard let flowValue = JSValue(object: flowDict, in: context) else { return nil }
        context.setObject(flowValue, forKeyedSubscript: "flow" as NSString)

        let fullScript = rule.code + "\ntransform(flow);"
        guard let result = context.evaluateScript(fullScript),
              !result.isNull, !result.isUndefined else { return nil }

        let statusValue = result.objectForKeyedSubscript("status")
        let status: Int
        if let sv = statusValue, !sv.isNull, !sv.isUndefined, sv.isNumber {
            status = Int(sv.toInt32())
        } else {
            status = flow.response?.status ?? 200
        }
        let body = result.objectForKeyedSubscript("body")?.toString() ?? flow.response?.body ?? ""

        var headers: [String: String] = flow.response?.headers ?? [:]
        if let headersValue = result.objectForKeyedSubscript("headers"),
           !headersValue.isNull, !headersValue.isUndefined,
           let headersDict = headersValue.toDictionary() as? [String: String] {
            headers = headersDict
        }

        return ScriptResult(status: status, headers: headers, body: body)
    }
}
