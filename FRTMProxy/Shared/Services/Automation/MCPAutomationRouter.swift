import Foundation
import CoreFoundation

final class MCPAutomationRouter: @unchecked Sendable {
    typealias FlowProvider = @MainActor @Sendable () -> [MitmFlow]
    typealias RuleUpdater = @MainActor @Sendable (TrafficRuleDocument) throws -> Void
    typealias SessionStoreProvider = @MainActor @Sendable () -> (any SessionStoreProtocol)?

    private let flowProvider: FlowProvider
    private let ruleUpdater: RuleUpdater
    private let redactionPolicy: RedactionPolicy
    private let limits: AutomationLimits
    private let sessionStoreProvider: SessionStoreProvider

    init(
        redactionPolicy: RedactionPolicy = .defaults,
        limits: AutomationLimits = .defaults,
        sessionStore: (any SessionStoreProtocol)? = nil,
        sessionStoreProvider: SessionStoreProvider? = nil,
        flowProvider: @escaping FlowProvider,
        ruleUpdater: @escaping RuleUpdater
    ) {
        self.redactionPolicy = redactionPolicy
        self.limits = limits
        self.sessionStoreProvider = sessionStoreProvider ?? { sessionStore }
        self.flowProvider = flowProvider
        self.ruleUpdater = ruleUpdater
    }

    func handle(_ data: Data) async -> Data? {
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
            return await handleToolCall(id: id, parameters: request["params"] as? [String: Any] ?? [:])
        case "ping":
            return encode(success(id: id, result: [:]))
        default:
            return encode(error(id: id, code: -32601, message: "Method not found"))
        }
    }

    private func handleToolCall(id: Any?, parameters: [String: Any]) async -> Data? {
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
                let flows = await flowProvider()
                result = Array(flows.prefix(limit)).map(flowObject)
            case "query_flows":
                let query = arguments["query"] as? String ?? ""
                guard query.utf8.count <= 4096 else { throw RouterFailure.invalidArguments("Query exceeds 4096 bytes") }
                let offset = max(0, arguments["offset"] as? Int ?? 0)
                let limit = max(1, min(arguments["limit"] as? Int ?? 100, limits.maximumBatchItems))
                let flows = await flowProvider()
                let matching = try FlowFilter(searchText: query).applyCancellable(to: flows, using: FlowFilter.Cache())
                result = ["flows": Array(matching.dropFirst(offset).prefix(limit)).map(flowObject),
                          "total": matching.count, "nextOffset": offset + limit < matching.count ? offset + limit : NSNull()]
            case "analyze_flows":
                guard let ids = arguments["ids"] as? [String], !ids.isEmpty, ids.count <= 20 else {
                    throw RouterFailure.invalidArguments("Provide between 1 and 20 flow ids")
                }
                let flows = await flowProvider()
                result = try ids.map { id -> [String: Any] in
                    guard let flow = flows.first(where: { $0.id == id }) else {
                        throw RouterFailure.invalidArguments("Unknown flow id")
                    }
                    let status = flow.response?.status
                    let finding: String
                    if flow.captureError != nil { finding = "Transport error recorded" }
                    else if let status, status >= 500 { finding = "Server error: HTTP \(status)" }
                    else if let status, status >= 400 { finding = "Request failed: HTTP \(status)" }
                    else if ["response_headers", "response_stream"].contains(flow.event) { finding = "Response stream is active" }
                    else { finding = "No HTTP error recorded; inspect the redacted evidence" }
                    return ["sourceFlowID": id, "finding": finding, "evidence": flowObject(flow)]
                }
            case "get_flow":
                guard let flowID = arguments["id"] as? String,
                      let flow = await flowProvider().first(where: { $0.id == flowID }) else {
                    throw RouterFailure.invalidArguments("Unknown flow id")
                }
                result = flowObject(flow)
            case "list_sessions":
                guard let sessionStore = await sessionStoreProvider() else { throw RouterFailure.invalidArguments("Session history is unavailable") }
                let offset = try integerArgument("offset", default: 0, arguments: arguments)
                let limit = try integerArgument("limit", default: 100, arguments: arguments)
                guard offset >= 0, (1...limits.maximumBatchItems).contains(limit) else {
                    throw RouterFailure.invalidArguments("Invalid offset or limit")
                }
                let sessions = try await sessionStore.sessions()
                let page = sessions.dropFirst(offset).prefix(limit)
                result = ["sessions": page.map { session in
                    ["id": session.id.uuidString, "name": session.name,
                     "createdAt": session.createdAt.timeIntervalSince1970,
                     "updatedAt": session.updatedAt.timeIntervalSince1970,
                     "isActive": session.isActive, "flowCount": session.flowCount] as [String: Any]
                }, "nextOffset": page.count < sessions.count - min(offset, sessions.count) ? (offset + page.count) as Any : NSNull()]
            case "query_session_flows":
                guard let sessionStore = await sessionStoreProvider() else { throw RouterFailure.invalidArguments("Session history is unavailable") }
                let sessionID = try sessionID(arguments)
                guard (arguments["query"] == nil || arguments["query"] is String),
                      (arguments["cursor"] == nil || arguments["cursor"] is String) else {
                    throw RouterFailure.invalidArguments("Query and cursor must be strings")
                }
                let query = arguments["query"] as? String ?? ""
                let limit = try integerArgument("limit", default: 200, arguments: arguments)
                guard query.utf8.count <= 4096, (1...min(1000, limits.maximumBatchItems)).contains(limit) else {
                    throw RouterFailure.invalidArguments("Invalid query or page limit")
                }
                let cursor: CaptureSessionPageCursor?
                if let encoded = arguments["cursor"] as? String {
                    guard encoded.utf8.count <= 2048, let data = Data(base64Encoded: encoded),
                          let decoded = try? JSONDecoder().decode(CaptureSessionPageCursor.self, from: data),
                          decoded.timestamp.isFinite, !decoded.flowID.isEmpty else {
                        throw RouterFailure.invalidArguments("Invalid session cursor")
                    }
                    cursor = decoded
                } else { cursor = nil }
                try Task.checkCancellation()
                let page = try await sessionStore.page(in: sessionID, after: cursor, limit: limit)
                let matching = try FlowFilter(searchText: query).applyCancellable(to: page.flows.map(\.flow), using: FlowFilter.Cache())
                let next: Any = try page.nextCursor.map { try JSONEncoder().encode($0).base64EncodedString() } ?? NSNull()
                result = ["flows": matching.map(flowObject), "nextCursor": next,
                          "scannedReadableFlows": page.flows.count, "corruptFlowCount": page.corruptFlowIDs.count,
                          "sessionID": sessionID.uuidString]
            case "get_session_flow":
                guard let sessionStore = await sessionStoreProvider(), let id = arguments["id"] as? String, !id.isEmpty else {
                    throw RouterFailure.invalidArguments("Session history and flow id are required")
                }
                guard let stored = try await sessionStore.flow(id: id, in: sessionID(arguments)) else {
                    throw RouterFailure.invalidArguments("Unknown session flow id")
                }
                result = flowObject(stored.flow)
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
                try await ruleUpdater(document)
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

    private func integerArgument(_ name: String, default defaultValue: Int, arguments: [String: Any]) throws -> Int {
        guard let value = arguments[name] else { return defaultValue }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = value as? Int, number.doubleValue == Double(integer) else {
            throw RouterFailure.invalidArguments("\(name) must be an integer")
        }
        return integer
    }

    private func sessionID(_ arguments: [String: Any]) throws -> UUID {
        guard let raw = arguments["sessionID"] as? String, let id = UUID(uuidString: raw) else {
            throw RouterFailure.invalidArguments("A valid sessionID is required")
        }
        return id
    }

    private func flowObject(_ flow: MitmFlow) -> [String: Any] {
        var result: [String: Any] = [
            "id": flow.id,
            "event": flow.event,
            "host": flow.host,
            "path": flow.path
        ]
        if let timestamp = flow.timestamp { result["timestamp"] = timestamp }
        if let duration = flow.duration { result["durationSeconds"] = duration }
        if let response = flow.response {
            result["responsePreviewTruncated"] = response.bodyTruncated ?? false
            if let inspection = ProtocolInspector.inspect(body: response.body, headers: response.headers ?? [:]) {
                result["responseProtocol"] = inspection.kind.displayName
            }
        }
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
        var result: [[String: Any]] = [
            [
                "name": "list_flows",
                "description": "List recent FRTMProxy flows with sensitive data redacted.",
                "inputSchema": ["type": "object", "properties": ["limit": ["type": "integer", "minimum": 1, "maximum": limits.maximumBatchItems]]]
            ],
            [
                "name": "query_flows",
                "description": "Search the bounded live capture with FRTMProxy filters; results are redacted and paginated.",
                "inputSchema": ["type": "object", "properties": ["query": ["type": "string"], "offset": ["type": "integer", "minimum": 0], "limit": ["type": "integer", "minimum": 1, "maximum": limits.maximumBatchItems]]],
                "annotations": ["readOnlyHint": true]
            ],
            [
                "name": "analyze_flows",
                "description": "Local deterministic diagnosis of selected flows, with redacted source evidence; performs no actions.",
                "inputSchema": ["type": "object", "properties": ["ids": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 20]], "required": ["ids"]],
                "annotations": ["readOnlyHint": true]
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
        // Storage is initialized asynchronously and can recover after launch.
        // Keep discovery stable; calls report unavailability until it is ready.
        do {
            result += [
                ["name": "list_sessions", "description": "List captured sessions with paginated metadata; returns no flow bodies or notes.",
                 "inputSchema": ["type": "object", "properties": ["offset": ["type": "integer", "minimum": 0], "limit": ["type": "integer", "minimum": 1, "maximum": limits.maximumBatchItems]]],
                 "annotations": ["readOnlyHint": true]],
                ["name": "query_session_flows", "description": "Search one page of encrypted session history using FRTMProxy filters. Limit bounds examined stored rows. Results are redacted. Continue with nextCursor even if the current page has no matches; null means the scan is finished. Corrupt rows are counted, never silently treated as matching data.",
                 "inputSchema": ["type": "object", "properties": ["sessionID": ["type": "string"], "query": ["type": "string"], "cursor": ["type": "string"], "limit": ["type": "integer", "minimum": 1, "maximum": min(1000, limits.maximumBatchItems)]], "required": ["sessionID"]],
                 "annotations": ["readOnlyHint": true]],
                ["name": "get_session_flow", "description": "Read a flow from encrypted session history by session and flow id; sensitive data is redacted and bodies are omitted by default.",
                 "inputSchema": ["type": "object", "properties": ["sessionID": ["type": "string"], "id": ["type": "string"]], "required": ["sessionID", "id"]],
                 "annotations": ["readOnlyHint": true]]
            ]
        }
        return result
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
