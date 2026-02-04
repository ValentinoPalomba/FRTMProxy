import Combine
import Foundation

@MainActor
final class ProxyMockService: ObservableObject, ProxyServiceProtocol {
    @Published private(set) var flows: [String: MitmFlow] = [:]
    @Published private(set) var isRunning = false

    nonisolated(unsafe) var onLog: ((String) -> Void)?

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { $flows.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }

    private var ticker: Timer?
    private var tick = 0
    private var activePort = 8080

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws {
        activePort = port ?? 8080
        guard !isRunning else { return }

        isRunning = true
        tick = 0
        flows = Dictionary(uniqueKeysWithValues: initialFlows().map { ($0.id, $0) })
        startTicker()

        onLog?("[MOCK] ProxyMockService started on port \(activePort)\n")
        if restrictToHosts, !hosts.isEmpty {
            onLog?("[MOCK] Host filter active: \(hosts.joined(separator: ", "))\n")
        }
    }

    func stopProxy() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        onLog?("[MOCK] ProxyMockService stopped\n")
    }

    func clearFlows() {
        flows.removeAll()
        onLog?("[MOCK] Flows cleared\n")
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
        onLog?("[MOCK] Response updated for \(flowID)\n")
    }

    func mockRule(_ rule: MapRule) {
        onLog?("[MOCK] Rule applied: \(rule.key)\n")
    }

    func deleteRule(forKey key: String) {
        onLog?("[MOCK] Rule deleted: \(key)\n")
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
                url: oldRequest?.url ?? "https://api.mock.local/edited",
                headers: requestHeaders,
                body: body
            )
        }
        onLog?("[MOCK] Request updated for \(flowID)\n")
    }

    func applyTrafficProfile(_ profile: TrafficProfile) {
        onLog?("[MOCK] Traffic profile: \(profile.name)\n")
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
            client: MitmFlow.Client(ip: "127.0.0.1", port: 53422),
            clientApp: FlowClientApp(id: "com.apple.dt.Xcode", displayName: "Xcode"),
            breakpoint: nil
        )
        flows[retryID] = flow
        onLog?("[MOCK] Retried flow from \(flowID)\n")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard var retried = flows[retryID] else { return }
            retried.response = MitmFlow.Response(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: "{\n  \"retry\": true,\n  \"source\": \"\(flowID)\"\n}"
            )
            retried.event = "response"
            retried.timestamp = Date().timeIntervalSince1970
            flows[retryID] = retried
        }
    }

    func updateBreakpointRule(_ rule: FlowBreakpointRule) {
        onLog?("[MOCK] Breakpoint rule updated: \(rule.key)\n")
    }

    func deleteBreakpointRule(forKey key: String) {
        onLog?("[MOCK] Breakpoint rule deleted: \(key)\n")
    }

    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {
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
        onLog?("[MOCK] Breakpoint resumed for \(flowID) (\(phase.rawValue))\n")
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.emitLiveFlow()
            }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func emitLiveFlow() {
        guard isRunning else { return }
        tick += 1

        let now = Date().timeIntervalSince1970
        let flowID = "live-\(tick)"
        let status = [200, 201, 204, 400, 401, 429, 500][tick % 7]
        let method = ["GET", "POST", "PATCH"][tick % 3]
        let host = ["api.staging.frtm.dev", "catalog.frtm.dev", "cdn.frtm.dev"][tick % 3]
        let path = ["/v1/session/ping", "/v1/products", "/v1/feature-flags"][tick % 3]
        let app = ["Simulator", "Xcode", "Safari"][tick % 3]

        let body = """
        {
          "tick": \(tick),
          "status": \(status),
          "host": "\(host)",
          "path": "\(path)"
        }
        """

        let flow = MitmFlow(
            id: flowID,
            request: MitmFlow.Request(
                method: method,
                url: "https://\(host)\(path)?tick=\(tick)",
                headers: [
                    "Accept": "application/json",
                    "User-Agent": "FRTMProxyMock/1.0"
                ],
                body: method == "GET" ? nil : "{\"tick\": \(tick)}"
            ),
            response: MitmFlow.Response(
                status: status,
                headers: ["Content-Type": "application/json"],
                body: body
            ),
            event: "response",
            timestamp: now,
            client: MitmFlow.Client(ip: "127.0.0.1", port: 53000 + tick),
            clientApp: FlowClientApp(id: "mock.\(app.lowercased())", displayName: app),
            breakpoint: nil
        )

        flows[flowID] = flow
        trimIfNeeded(maxCount: 60)
    }

    private func updateFlow(_ flowID: String, mutate: (inout MitmFlow) -> Void) {
        guard var flow = flows[flowID] else { return }
        mutate(&flow)
        flow.timestamp = Date().timeIntervalSince1970
        flows[flowID] = flow
    }

    private func trimIfNeeded(maxCount: Int) {
        guard flows.count > maxCount else { return }
        let keep = flows.values
            .sorted(by: { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) })
            .prefix(maxCount)
        flows = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }

    private func initialFlows() -> [MitmFlow] {
        let now = Date().timeIntervalSince1970
        return [
            makeFlow(
                id: "f-html",
                timestamp: now - 2,
                method: "GET",
                url: "https://www.frtm.dev/home?preview=true",
                status: 200,
                requestBody: nil,
                responseBody: "<!doctype html><html><head><title>FRTM</title></head><body><h1>Dashboard</h1></body></html>",
                responseHeaders: ["Content-Type": "text/html; charset=utf-8"],
                clientIP: "127.0.0.1",
                clientPort: 53111,
                appName: "Safari"
            ),
            makeFlow(
                id: "f-json",
                timestamp: now - 6,
                method: "POST",
                url: "https://api.frtm.dev/v1/auth/login",
                status: 200,
                requestBody: "{\"email\":\"dev@frtm.dev\"}",
                responseBody: "{\n  \"token\": \"mock-token\",\n  \"expiresIn\": 3600\n}",
                responseHeaders: ["Content-Type": "application/json"],
                clientIP: "127.0.0.1",
                clientPort: 53112,
                appName: "Simulator"
            ),
            makeFlow(
                id: "f-xml",
                timestamp: now - 9,
                method: "GET",
                url: "https://api.frtm.dev/v1/feed.xml",
                status: 200,
                requestBody: nil,
                responseBody: "<feed><entry id=\"1\"><title>News</title></entry></feed>",
                responseHeaders: ["Content-Type": "application/xml"],
                clientIP: "127.0.0.1",
                clientPort: 53113,
                appName: "Xcode"
            ),
            makeFlow(
                id: "f-mapped",
                timestamp: now - 13,
                method: "GET",
                url: "https://api.frtm.dev/v1/catalog?page=1",
                status: 200,
                requestBody: nil,
                responseBody: "{\n  \"source\": \"map-local\",\n  \"items\": []\n}",
                responseHeaders: [
                    "Content-Type": "application/json",
                    "X-Map-Local": "1"
                ],
                clientIP: "127.0.0.1",
                clientPort: 53114,
                appName: "Simulator"
            ),
            makeFlow(
                id: "f-breakpoint",
                timestamp: now - 16,
                method: "PATCH",
                url: "https://api.frtm.dev/v1/profile",
                status: 202,
                requestBody: "{\"nickname\":\"octo\"}",
                responseBody: "{\n  \"pending\": true\n}",
                responseHeaders: ["Content-Type": "application/json"],
                clientIP: "127.0.0.1",
                clientPort: 53115,
                appName: "Postman",
                breakpoint: FlowBreakpointMetadata(phase: .response, state: .waiting, key: "api.frtm.dev|/v1/profile")
            )
        ]
    }

    private func makeFlow(
        id: String,
        timestamp: TimeInterval,
        method: String,
        url: String,
        status: Int,
        requestBody: String?,
        responseBody: String?,
        responseHeaders: [String: String],
        clientIP: String,
        clientPort: Int,
        appName: String,
        breakpoint: FlowBreakpointMetadata? = nil
    ) -> MitmFlow {
        MitmFlow(
            id: id,
            request: MitmFlow.Request(
                method: method,
                url: url,
                headers: [
                    "Accept": "*/*",
                    "User-Agent": "FRTMProxyMock/1.0"
                ],
                body: requestBody
            ),
            response: MitmFlow.Response(
                status: status,
                headers: responseHeaders,
                body: responseBody
            ),
            event: "response",
            timestamp: timestamp,
            client: MitmFlow.Client(ip: clientIP, port: clientPort),
            clientApp: FlowClientApp(id: FlowClientApp.normalizedID(appName), displayName: appName),
            breakpoint: breakpoint
        )
    }
}
