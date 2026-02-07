import Combine
import Foundation
import ProxyCore

@MainActor
final class NIOProxyService: ObservableObject, ProxyServiceProtocol {
    @Published private(set) var flows: [String: MitmFlow] = [:]
    @Published private(set) var isRunning: Bool = false

    nonisolated(unsafe) var onLog: ((String) -> Void)?

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { $flows.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }

    private let maxFlowsStored = 500
    private var engine: ProxyEngine?
    private var eventsTask: Task<Void, Never>?
    private var activePort: Int = 8080

    private let mapRuleRegistry = MapRuleRegistry()
    private lazy var breakpointController = BreakpointController(service: self)

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws {
        if isRunning {
            return
        }

        let selectedPort = port ?? activePort
        activePort = selectedPort

        var hostFilter = ProxyConfiguration.HostFilter()
        if restrictToHosts {
            hostFilter.whitelistEnabled = true
            hostFilter.whitelistPatterns = hosts.map(Self.hostAllowRegex(for:))
            // When whitelisting, ignore the default blacklist to match mitmproxy allow_hosts behavior.
            hostFilter.blacklistEnabled = false
            hostFilter.blacklistPatterns = []
        }

        let config = ProxyConfiguration(
            listenHost: "127.0.0.1",
            listenPort: selectedPort,
            enableMITM: true,
            enableHTTP2: true,
            upstreamTLSVerification: .trustAll,
            socks5InboundEnabled: true,
            hostFilter: hostFilter
        )

        let interceptors: [any ProxyInterceptor] = [
            BreakpointInterceptor(controller: breakpointController),
            MapRuleInterceptor(registry: mapRuleRegistry),
        ]

        let engine = try ProxyEngine(configuration: config, interceptors: interceptors)
        self.engine = engine

        // Start consuming events before starting the engine to avoid losing early logs.
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            for await event in engine.events {
                await self?.handle(event: event)
            }
        }

        do {
            try await engine.start()
            isRunning = true
            onLog?("[PROXY] SwiftNIO ProxyCore started on port \(selectedPort)\n")
            if restrictToHosts {
                onLog?("[PROXY] Host filter active: \(hosts.joined(separator: ", "))\n")
            }
        } catch {
            self.engine = nil
            eventsTask?.cancel()
            eventsTask = nil
            throw error
        }
    }

    func stopProxy() {
        guard let engine else { return }
        Task { [engine, weak self] in
            await self?.breakpointController.cancelAll()
            await engine.stop()
            await MainActor.run {
                self?.engine = nil
                self?.isRunning = false
                self?.onLog?("[PROXY] SwiftNIO ProxyCore stopped\n")
            }
        }
    }

    func clearFlows() {
        flows.removeAll()
        onLog?("[PROXY] Flows cleared\n")
    }

    func mockResponse(for flowID: String, body: String) {
        mockResponse(for: flowID, body: body, status: nil, headers: nil)
    }

    func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?) {
        updateFlow(flowID) { flow in
            var responseHeaders = flow.response?.headers ?? [:]
            if let headers {
                headers.forEach { responseHeaders[$0.key] = $0.value }
            }
            responseHeaders["X-Map-Local"] = "1"
            flow.response = MitmFlow.Response(
                status: status ?? flow.response?.status ?? 200,
                headers: responseHeaders,
                body: body
            )
        }
        onLog?("[MAP LOCAL] response updated for \(flowID) (UI-only)\n")
    }

    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {
        updateFlow(flowID) { flow in
            var requestHeaders = flow.request?.headers ?? [:]
            if let headers {
                headers.forEach { requestHeaders[$0.key] = $0.value }
            }
            let oldRequest = flow.request
            flow.request = MitmFlow.Request(
                method: oldRequest?.method ?? "GET",
                url: oldRequest?.url ?? "https://example.invalid/edited",
                headers: requestHeaders,
                body: body
            )
        }
        onLog?("[MAP LOCAL] request updated for \(flowID) (UI-only)\n")
    }

    func mockRule(_ rule: MapRule) {
        Task {
            await mapRuleRegistry.upsert(rule)
        }
        onLog?("[MAP LOCAL] rule updated for \(rule.key)\n")
    }

    func deleteRule(forKey key: String) {
        Task {
            await mapRuleRegistry.delete(key)
        }
        onLog?("[MAP LOCAL] rule removed for \(key)\n")
    }

    func applyTrafficProfile(_ profile: TrafficProfile) {
        onLog?("[TRAFFIC] profile \(profile.name) (not yet enforced by ProxyCore)\n")
    }

    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String]) {
        let retryID = "retry-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970

        let request = MitmFlow.Request(method: method, url: url, headers: headers, body: body)
        let flow = MitmFlow(
            id: retryID,
            request: request,
            response: nil,
            event: "request",
            timestamp: now,
            client: MitmFlow.Client(ip: "127.0.0.1", port: nil),
            clientApp: nil,
            breakpoint: nil
        )
        flows[retryID] = flow
        onLog?("[RETRY] sending \(method) \(url)\n")

        Task { [weak self] in
            guard let self else { return }
            guard let targetURL = URL(string: url) else { return }
            var req = URLRequest(url: targetURL)
            req.httpMethod = method
            req.httpBody = body?.data(using: .utf8)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                var resHeaders: [String: String] = [:]
                if let http {
                    for (k, v) in http.allHeaderFields {
                        if let ks = k as? String, let vs = v as? String {
                            resHeaders[ks] = vs
                        }
                    }
                }
                let bodyString = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"

                updateFlow(retryID) { f in
                    f.response = MitmFlow.Response(status: status, headers: resHeaders, body: bodyString)
                    f.event = "response"
                    f.timestamp = Date().timeIntervalSince1970
                }
            } catch {
                self.onLog?("[RETRY] failed: \(error)\n")
            }
        }
    }

    func updateBreakpointRule(_ rule: FlowBreakpointRule) {
        Task {
            await breakpointController.upsertRule(
                key: rule.key,
                interceptRequest: rule.interceptRequest,
                interceptResponse: rule.interceptResponse,
                enabled: rule.isEnabled
            )
        }
        onLog?("[BREAKPOINT] rule updated for \(rule.key)\n")
    }

    func deleteBreakpointRule(forKey key: String) {
        Task {
            await breakpointController.deleteRule(forKey: key)
        }
        onLog?("[BREAKPOINT] rule removed for \(key)\n")
    }

    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {
        Task {
            await breakpointController.resume(
                flowID: flowID,
                phase: phase,
                requestPayload: requestPayload,
                responsePayload: responsePayload
            )
        }

        // Optimistic UI update.
        updateFlow(flowID) { flow in
            flow.breakpoint = nil
            if let requestPayload {
                flow.request = MitmFlow.Request(
                    method: requestPayload.method,
                    url: requestPayload.url,
                    headers: requestPayload.headers,
                    body: requestPayload.body
                )
            }
            if let responsePayload {
                flow.response = MitmFlow.Response(
                    status: responsePayload.status,
                    headers: responsePayload.headers,
                    body: responsePayload.body
                )
            }
        }
        onLog?("[BREAKPOINT] resume requested for \(flowID) (\(phase.rawValue))\n")
    }

    // MARK: - Events

    private func handle(event: ProxyEvent) async {
        switch event {
        case .log(let line):
            onLog?(line)

        case .error(let err):
            onLog?("[ERR] \(err.requestID ?? "-") \(err.message)\n")

        case .request(let req):
            mergeRequest(req)

        case .response(let res):
            mergeResponse(res)

        case .webSocketMessage(let msg):
            onLog?("[WS] id=\(msg.requestID) dir=\(msg.direction) bytes=\(msg.data.count)\n")

        case .sseEvent(let e):
            onLog?("[SSE] id=\(e.requestID) event=\(e.event ?? "") bytes=\(e.data.utf8.count)\n")
        }
    }

    private func mergeRequest(_ req: ProxyRequest) {
        let now = req.timestamp.timeIntervalSince1970
        let bodyString = req.bodyPreview.flatMap { String(data: $0, encoding: .utf8) }

        let incoming = MitmFlow(
            id: req.id,
            request: MitmFlow.Request(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: bodyString
            ),
            response: nil,
            event: "request",
            timestamp: now,
            client: req.client.map { MitmFlow.Client(ip: $0.ip, port: $0.port) },
            clientApp: nil,
            breakpoint: nil
        )

        if var existing = flows[req.id] {
            existing.request = incoming.request
            existing.event = "request"
            existing.timestamp = existing.timestamp ?? incoming.timestamp
            existing.client = existing.client ?? incoming.client
            flows[req.id] = existing
        } else {
            flows[req.id] = incoming
        }

        trimOldFlowsIfNeeded()
    }

    private func mergeResponse(_ res: ProxyResponse) {
        let now = res.timestamp.timeIntervalSince1970
        let bodyString = res.bodyPreview.flatMap { String(data: $0, encoding: .utf8) }

        let response = MitmFlow.Response(
            status: res.statusCode,
            headers: res.headers,
            body: bodyString
        )

        if var existing = flows[res.requestID] {
            existing.response = response
            existing.event = "response"
            existing.timestamp = existing.timestamp ?? now
            flows[res.requestID] = existing
        } else {
            flows[res.requestID] = MitmFlow(
                id: res.requestID,
                request: nil,
                response: response,
                event: "response",
                timestamp: now,
                client: nil,
                clientApp: nil,
                breakpoint: nil
            )
        }

        trimOldFlowsIfNeeded()
    }

    private func trimOldFlowsIfNeeded() {
        guard flows.count > maxFlowsStored else { return }
        let ordered = flows.values.sorted { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
        let trimmed = ordered.prefix(maxFlowsStored)
        var newDict: [String: MitmFlow] = [:]
        trimmed.forEach { newDict[$0.id] = $0 }
        flows = newDict
        onLog?("[PERF] Flows limited to \(maxFlowsStored)\n")
    }

    private func updateFlow(_ flowID: String, mutate: (inout MitmFlow) -> Void) {
        guard var flow = flows[flowID] else { return }
        mutate(&flow)
        flows[flowID] = flow
    }

    // MARK: - Breakpoints (called from BreakpointController)

    fileprivate func markBreakpointWaiting(flowID: String, phase: FlowBreakpointPhase, key: String, request: ProxyRequest, response: ProxyResponse?) {
        let requestTimestamp = request.timestamp.timeIntervalSince1970

        var flow = flows[flowID] ?? MitmFlow(
            id: flowID,
            request: nil,
            response: nil,
            event: "request",
            timestamp: requestTimestamp,
            client: request.client.map { MitmFlow.Client(ip: $0.ip, port: $0.port) },
            clientApp: nil,
            breakpoint: nil
        )

        let requestBodyString = request.bodyPreview.flatMap { String(data: $0, encoding: .utf8) }
        flow.request = MitmFlow.Request(method: request.method, url: request.url, headers: request.headers, body: requestBodyString)
        flow.client = flow.client ?? request.client.map { MitmFlow.Client(ip: $0.ip, port: $0.port) }

        if let response {
            let responseTimestamp = response.timestamp.timeIntervalSince1970
            let responseBodyString = response.bodyPreview.flatMap { String(data: $0, encoding: .utf8) }
            flow.response = MitmFlow.Response(status: response.statusCode, headers: response.headers, body: responseBodyString)
            flow.event = "response"
            flow.timestamp = flow.timestamp ?? responseTimestamp
        } else {
            flow.event = "request"
            flow.timestamp = flow.timestamp ?? requestTimestamp
        }

        flow.breakpoint = FlowBreakpointMetadata(phase: phase, state: .waiting, key: key)
        flows[flowID] = flow
    }

    fileprivate func clearBreakpoint(flowID: String) {
        guard var flow = flows[flowID] else { return }
        flow.breakpoint = nil
        flows[flowID] = flow
    }

    private static func hostAllowRegex(for host: String) -> String {
        "(^|\\\\.)" + NSRegularExpression.escapedPattern(for: host) + "$"
    }
}

// MARK: - Map Rule Interceptor

private actor MapRuleRegistry {
    private var rulesByKey: [String: MapRule] = [:]

    func upsert(_ rule: MapRule) {
        rulesByKey[Self.normalized(rule.key)] = rule
    }

    func delete(_ key: String) {
        rulesByKey.removeValue(forKey: Self.normalized(key))
    }

    func match(request: ProxyRequest) -> MapRule? {
        guard
            let url = URL(string: request.url),
            let host = url.host
        else {
            return nil
        }

        let path = url.path.isEmpty ? "/" : url.path
        let baseKey = MapRuleKeyBuilder.baseKey(host: host, path: path)

        let bodyString = request.bodyPreview.flatMap { String(data: $0, encoding: .utf8) }
        let fullKey = MapRuleKeyBuilder.makeKey(
            host: host,
            path: path,
            method: request.method,
            url: request.url,
            headers: request.headers,
            body: bodyString
        )

        let normalizedFull = Self.normalized(fullKey)
        if let rule = rulesByKey[normalizedFull], rule.isEnabled {
            return rule
        }
        let normalizedBase = Self.normalized(baseKey)
        if let rule = rulesByKey[normalizedBase], rule.isEnabled {
            return rule
        }
        return nil
    }

    private static func normalized(_ key: String) -> String {
        // Strip "~N" disambiguation suffix if present.
        if let hash = key.firstIndex(of: "#") {
            let base = key[..<hash]
            let suffix = key[key.index(after: hash)...]
            if let tilde = suffix.firstIndex(of: "~") {
                let tag = suffix[..<tilde]
                return base + "#" + tag
            }
            return key
        }
        if let tilde = key.firstIndex(of: "~") {
            return String(key[..<tilde])
        }
        return key
    }
}

private struct MapRuleInterceptor: ProxyInterceptor {
    let registry: MapRuleRegistry

    var priority: Int { -500 }

    func execute(_ request: ProxyRequest) async -> ProxyResponse? {
        guard let rule = await registry.match(request: request) else { return nil }

        var headers = rule.headers
        headers["X-Map-Local"] = "1"
        let bodyData = Data(rule.body.utf8)

        return ProxyResponse(
            requestID: request.id,
            httpVersion: request.httpVersion,
            streamID: request.streamID,
            statusCode: rule.status,
            headers: headers,
            bodyPreview: bodyData,
            bodyIsTruncated: false,
            rawBodySize: bodyData.count
        )
    }
}

// MARK: - Breakpoints

private actor BreakpointController {
    private struct Rule: Sendable {
        var key: String
        var interceptRequest: Bool
        var interceptResponse: Bool
        var enabled: Bool
    }

    private enum Phase: String, Sendable {
        case request
        case response

        init?(_ phase: FlowBreakpointPhase) {
            switch phase {
            case .request: self = .request
            case .response: self = .response
            }
        }
    }

    private struct WaiterKey: Hashable, Sendable {
        var flowID: String
        var phase: Phase
    }

    private struct ResumeDecision: Sendable {
        var requestPayload: BreakpointRequestPayload?
        var responsePayload: BreakpointResponsePayload?
    }

    private weak var service: NIOProxyService?

    private var rulesByKey: [String: Rule] = [:]
    private var waiters: [WaiterKey: CheckedContinuation<ResumeDecision, Never>] = [:]

    init(service: NIOProxyService) {
        self.service = service
    }

    func upsertRule(key: String, interceptRequest: Bool, interceptResponse: Bool, enabled: Bool) {
        rulesByKey[key] = Rule(key: key, interceptRequest: interceptRequest, interceptResponse: interceptResponse, enabled: enabled)
    }

    func deleteRule(forKey key: String) {
        rulesByKey.removeValue(forKey: key)
    }

    func cancelAll() async {
        let pending = waiters
        waiters.removeAll()
        for (key, cont) in pending {
            cont.resume(returning: ResumeDecision(requestPayload: nil, responsePayload: nil))
            await service?.clearBreakpoint(flowID: key.flowID)
        }
    }

    func interceptRequestIfNeeded(_ request: ProxyRequest) async -> ProxyRequest? {
        guard let rule = matchRule(forURL: request.url), rule.enabled, rule.interceptRequest else {
            return request
        }

        await service?.markBreakpointWaiting(
            flowID: request.id,
            phase: .request,
            key: rule.key,
            request: request,
            response: nil
        )

        let decision = await wait(flowID: request.id, phase: .request)
        await service?.clearBreakpoint(flowID: request.id)

        if let payload = decision.requestPayload {
            return applyRequestPayload(payload, to: request)
        }
        return request
    }

    func interceptResponseIfNeeded(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        guard let rule = matchRule(forURL: request.url), rule.enabled, rule.interceptResponse else {
            return response
        }

        await service?.markBreakpointWaiting(
            flowID: request.id,
            phase: .response,
            key: rule.key,
            request: request,
            response: response
        )

        let decision = await wait(flowID: request.id, phase: .response)
        await service?.clearBreakpoint(flowID: request.id)

        if let payload = decision.responsePayload {
            return applyResponsePayload(payload, to: response)
        }
        return response
    }

    func resume(flowID: String, phase: FlowBreakpointPhase, requestPayload: BreakpointRequestPayload?, responsePayload: BreakpointResponsePayload?) {
        guard let phase = Phase(phase) else { return }
        let key = WaiterKey(flowID: flowID, phase: phase)
        guard let cont = waiters.removeValue(forKey: key) else { return }
        cont.resume(returning: ResumeDecision(requestPayload: requestPayload, responsePayload: responsePayload))
    }

    private func wait(flowID: String, phase: Phase) async -> ResumeDecision {
        let key = WaiterKey(flowID: flowID, phase: phase)

        // If there's an existing waiter, reuse it to avoid leaking continuations.
        if waiters[key] != nil {
            return ResumeDecision(requestPayload: nil, responsePayload: nil)
        }

        return await withCheckedContinuation { cont in
            waiters[key] = cont
        }
    }

    private func matchRule(forURL urlString: String) -> Rule? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let key = host + path
        return rulesByKey[key]
    }

    private func applyRequestPayload(_ payload: BreakpointRequestPayload, to request: ProxyRequest) -> ProxyRequest {
        var updated = request
        updated.method = payload.method
        updated.url = payload.url
        updated.headers = payload.headers

        if let body = payload.body {
            let data = Data(body.utf8)
            updated.bodyPreview = data
            updated.bodyIsTruncated = false
            updated.rawBodySize = data.count
        } else {
            updated.bodyPreview = nil
            updated.bodyIsTruncated = false
            updated.rawBodySize = 0
        }

        return updated
    }

    private func applyResponsePayload(_ payload: BreakpointResponsePayload, to response: ProxyResponse) -> ProxyResponse {
        var updated = response
        updated.statusCode = payload.status
        updated.headers = payload.headers

        let data = Data(payload.body.utf8)
        updated.bodyPreview = data
        updated.bodyIsTruncated = false
        updated.rawBodySize = data.count

        return updated
    }
}

private struct BreakpointInterceptor: ProxyInterceptor {
    let controller: BreakpointController
    var priority: Int { -850 }

    func onRequest(_ request: ProxyRequest) async -> ProxyRequest? {
        await controller.interceptRequestIfNeeded(request)
    }

    func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        await controller.interceptResponseIfNeeded(request: request, response: response)
    }
}
