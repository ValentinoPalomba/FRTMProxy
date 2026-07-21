import Foundation

@MainActor
final class MCPAutomationRouter {
    typealias FlowProvider = @MainActor () -> [MitmFlow]
    typealias RuleUpdater = @MainActor (TrafficRuleDocument) -> Void

    private let flowProvider: FlowProvider
    private let ruleUpdater: RuleUpdater
    private let redactionPolicy: RedactionPolicy
    private let limits: AutomationLimits

    init(
        redactionPolicy: RedactionPolicy = .defaults,
        limits: AutomationLimits = .defaults,
        flowProvider: @escaping FlowProvider,
        ruleUpdater: @escaping RuleUpdater
    ) {
        self.redactionPolicy = redactionPolicy
        self.limits = limits
        self.flowProvider = flowProvider
        self.ruleUpdater = ruleUpdater
    }

    func handle(_ data: Data) -> Data? {
        guard data.count <= limits.maximumRequestBytes,
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return encode(error(id: nil, code: -32600, message: "Invalid Request"))
        }
        let id = request["id"]
        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            return encode(success(id: id, result: [
                "protocolVersion": "2025-03-26",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "FRTMProxy", "version": "1.0"]
            ]))
        case "tools/list":
            return encode(success(id: id, result: ["tools": tools]))
        case "tools/call":
            return handleToolCall(id: id, parameters: request["params"] as? [String: Any] ?? [:])
        case "ping":
            return encode(success(id: id, result: [:]))
        default:
            return encode(error(id: id, code: -32601, message: "Method not found"))
        }
    }

    private func handleToolCall(id: Any?, parameters: [String: Any]) -> Data? {
        guard let name = parameters["name"] as? String else {
            return encode(error(id: id, code: -32602, message: "Missing tool name"))
        }
        let arguments = parameters["arguments"] as? [String: Any] ?? [:]

        do {
            let result: Any
            switch name {
            case "list_flows":
                let requestedLimit = arguments["limit"] as? Int ?? 100
                let limit = max(1, min(requestedLimit, limits.maximumBatchItems))
                result = Array(flowProvider().prefix(limit)).map(flowObject)
            case "get_flow":
                guard let flowID = arguments["id"] as? String,
                      let flow = flowProvider().first(where: { $0.id == flowID }) else {
                    throw RouterFailure.invalidArguments("Unknown flow id")
                }
                result = flowObject(flow)
            case "replace_rules":
                guard let documentObject = arguments["document"] else {
                    throw RouterFailure.invalidArguments("Missing document")
                }
                let documentData = try JSONSerialization.data(withJSONObject: documentObject)
                let document = try JSONDecoder().decode(TrafficRuleDocument.self, from: documentData)
                try limits.validateBatch(itemCount: document.rules.count)
                let validationErrors = document.rules.flatMap { $0.matcher.validationErrors }
                guard validationErrors.isEmpty else {
                    throw RouterFailure.invalidArguments(validationErrors.joined(separator: "; "))
                }
                ruleUpdater(document)
                result = ["accepted": true, "count": document.rules.count]
            default:
                throw RouterFailure.unknownTool
            }
            return encode(success(id: id, result: [
                "content": [["type": "text", "text": jsonString(result)]],
                "isError": false
            ]))
        } catch RouterFailure.unknownTool {
            return encode(error(id: id, code: -32602, message: "Unknown tool"))
        } catch {
            return encode(success(id: id, result: [
                "content": [["type": "text", "text": error.localizedDescription]],
                "isError": true
            ]))
        }
    }

    private func flowObject(_ flow: MitmFlow) -> [String: Any] {
        var result: [String: Any] = [
            "id": flow.id,
            "event": flow.event,
            "host": flow.host,
            "path": flow.path
        ]
        if let timestamp = flow.timestamp { result["timestamp"] = timestamp }
        if let request = flow.request {
            let redacted = try? AutomationRedactor.redact(
                .init(url: request.url, headers: request.headers, body: request.body),
                using: redactionPolicy
            )
            result["request"] = messageObject(redacted, method: request.method, status: nil)
        }
        if let response = flow.response {
            let redacted = try? AutomationRedactor.redact(
                .init(headers: response.headers ?? [:], body: response.body),
                using: redactionPolicy
            )
            result["response"] = messageObject(redacted, method: nil, status: response.status)
        }
        return result
    }

    private func messageObject(
        _ message: RedactedAutomationHTTPMessage?,
        method: String?,
        status: Int?
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        if let method { result["method"] = method }
        if let status { result["status"] = status }
        if let url = message?.url { result["url"] = url }
        result["headers"] = message?.headers ?? [:]
        if let body = message?.body { result["body"] = body }
        result["bodyOmitted"] = message?.bodyWasOmitted ?? true
        result["bodyTruncated"] = message?.bodyWasTruncated ?? false
        return result
    }

    private var tools: [[String: Any]] {
        [
            [
                "name": "list_flows",
                "description": "List recent FRTMProxy flows with sensitive data redacted.",
                "inputSchema": ["type": "object", "properties": ["limit": ["type": "integer", "minimum": 1, "maximum": limits.maximumBatchItems]]]
            ],
            [
                "name": "get_flow",
                "description": "Read one captured flow by id with sensitive data redacted.",
                "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]]
            ],
            [
                "name": "replace_rules",
                "description": "Atomically replace the versioned FRTMProxy traffic rule document.",
                "inputSchema": ["type": "object", "properties": ["document": ["type": "object"]], "required": ["document"]]
            ]
        ]
    }

    private func success(id: Any?, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func encode(_ object: [String: Any]) -> Data? {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           data.count <= limits.maximumResponseBytes {
            return data
        }
        let fallback: [String: Any] = [
            "jsonrpc": "2.0",
            "id": object["id"] ?? NSNull(),
            "error": ["code": -32603, "message": "Response exceeds the configured safety limit"]
        ]
        return try? JSONSerialization.data(withJSONObject: fallback, options: [.sortedKeys])
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }

    private enum RouterFailure: LocalizedError {
        case unknownTool
        case invalidArguments(String)

        var errorDescription: String? {
            switch self {
            case .unknownTool: "Unknown tool"
            case .invalidArguments(let message): message
            }
        }
    }
}
