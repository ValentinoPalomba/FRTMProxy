import Foundation
import Combine
import AppKit

struct MitmproxyConfig {
    var port: Int
    
    init(
        port: Int = 8080
    ) {
        self.port = port
    }
}

enum MitmproxyServiceError: LocalizedError {
    case executableNotFound(String)
    case failedToRun(String)
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "mitmdump executable not found at: \(path)"
        case .failedToRun(let reason):
            return "Unable to run mitmdump: \(reason)"
        }
    }
}

private enum MitmdumpWarmupState: Equatable {
    case idle
    case warming
    case ready
    case failed(String)
}

@MainActor
final class MitmproxyService: ObservableObject, ProxyServiceProtocol {
    private let config: MitmproxyConfig
    private var process: Process?
    private var commandHandle: FileHandle?
    private let maxFlowsStored = 500
    private var flowWeights: [String: Int] = [:]
    private var retainedPayloadBytes = 0
    private var lastCacheNotice: ContinuousClock.Instant?
    private var appTerminationObserver: NSObjectProtocol?
    private var workspaceTerminationObserver: NSObjectProtocol?
    private var warmupState: MitmdumpWarmupState = .idle
    private var warmupProcess: Process?
    private var prewarmTask: Task<Void, Never>?
    private var cachedMitmdumpURL: URL?
    private var rulesRevision = 0
    private var rulesAckTask: Task<Void, Never>?
    private var startupID = UUID()
    private var bridgeReady = false
    private var isStarting = false
    /// Serializza le scritture su stdin del bridge fuori dal MainActor: una
    /// pipe piena bloccherebbe la UI, e la write può fallire (EPIPE) se il
    /// processo è morto — qui viene gestita senza bloccare né crashare.
    private let commandWriteQueue = DispatchQueue(label: "com.frtmproxy.command-write", qos: .userInitiated)
    
    var onLog: ((String) -> Void)?
    
    /// Proxy running?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var flows: [String: MitmFlow] = [:]
    private let flowEventsSubject = PassthroughSubject<MitmFlow, Never>()

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { $flows.eraseToAnyPublisher() }
    var flowEventsPublisher: AnyPublisher<MitmFlow, Never> { flowEventsSubject.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }
    
    nonisolated init(config: MitmproxyConfig) {
        self.config = config
        Task { @MainActor in
            self.setupTerminationObservers()
            self.schedulePrewarmMitmdumpExecutableIfNeeded()
        }
    }
    
    deinit {
        if let observer = appTerminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = workspaceTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        // Cleanup sincrono. Un `Task { @MainActor [weak self] }` schedulato qui
        // girerebbe dopo che l'istanza è già deallocata (`self == nil`), quindi
        // i processi figli non verrebbero MAI terminati e mitmdump resterebbe
        // orfano. In deinit l'istanza non è più condivisa: l'accesso diretto
        // alle proprietà è sicuro e la terminazione è immediata.
        prewarmTask?.cancel()
        process?.terminate()
        warmupProcess?.terminate()
    }
    
    func startProxy(port: Int? = nil, restrictToHosts: Bool = false, hosts: [String] = []) async throws {
        guard !isRunning, !isStarting else { return }
        let selectedPort = port ?? config.port
        guard (1024...65535).contains(selectedPort) else {
            throw MitmproxyServiceError.failedToRun("Port must be between 1024 and 65535")
        }
        let executableURL = try bundledMitmdumpExecutableURL()
        let scriptURL = try bridgeScriptURL()
        let launchID = UUID()
        startupID = launchID
        bridgeReady = false
        isStarting = true
        defer { if startupID == launchID { isStarting = false } }

        let bodyEnvironment = try await Task.detached(priority: .userInitiated) {
            try CaptureBodyStore.environment()
        }.value
        try Task.checkCancellation()
        guard startupID == launchID else { throw CancellationError() }

        let result = try await Self.launchProcess(
            executableURL: executableURL,
            scriptURL: scriptURL,
            selectedPort: selectedPort,
            restrictToHosts: restrictToHosts,
            hosts: hosts,
            launchID: launchID,
            bodyEnvironment: bodyEnvironment,
            onLine: { [weak self] line in
                self?.handleIncomingLine(line, launchID: launchID)
            },
            onError: { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self, self.startupID == launchID else { return }
                    self.onLog?("[ERR] " + text)
                }
            },
            onTermination: { [weak self] in
                Task { @MainActor in
                    guard let self, self.startupID == launchID else { return }
                    self.isRunning = false
                    self.bridgeReady = false
                }
            }
        )
        guard startupID == launchID else {
            if result.process.isRunning { result.process.terminate() }
            throw CancellationError()
        }
        process = result.process
        commandHandle = result.commandHandle
        do {
            let deadline = ContinuousClock.now + .seconds(30)
            while !bridgeReady {
                try Task.checkCancellation()
                guard startupID == launchID, result.process.isRunning else {
                    throw MitmproxyServiceError.failedToRun("Proxy exited before becoming ready")
                }
                guard ContinuousClock.now < deadline else {
                    throw MitmproxyServiceError.failedToRun("Proxy startup timed out")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard startupID == launchID, result.process.isRunning else { throw CancellationError() }
            isRunning = true
            onLog?("[PROXY] ready on port \(selectedPort)\n")
        } catch {
            if startupID == launchID { stopProxy() }
            throw error
        }
    }

    private struct LaunchResult {
        let process: Process
        let commandHandle: FileHandle
    }

    private static func launchProcess(
        executableURL: URL,
        scriptURL: URL,
        selectedPort: Int,
        restrictToHosts: Bool,
        hosts: [String],
        launchID: UUID,
        bodyEnvironment: [String: String],
        onLine: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onTermination: @escaping () -> Void
    ) async throws -> LaunchResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                var environment = ProcessInfo.processInfo.environment
                environment.merge(bodyEnvironment) { _, value in value }
                environment["FRTMPROXY_STARTUP_ID"] = launchID.uuidString
                environment["FRTMPROXY_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
                if let workerURL = Bundle.main.executableURL {
                    environment["FRTMPROXY_SCRIPT_WORKER"] = workerURL.path
                }
                process.environment = environment
                process.arguments = MitmproxyService.buildArguments(
                    scriptURL: scriptURL,
                    selectedPort: selectedPort,
                    restrictToHosts: restrictToHosts,
                    hosts: hosts
                )

                let pipe = Pipe()
                let errorPipe = Pipe()
                let inputPipe = Pipe()
                let stdoutLineBuffer = LineBuffer(onOverflow: { onError("Bridge frame exceeded 16 MB and was discarded\n") }, onLine: onLine)

                process.standardOutput = pipe
                process.standardError = errorPipe
                process.standardInput = inputPipe

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    stdoutLineBuffer.append(chunk)
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        onError(text)
                    }
                }

                process.terminationHandler = { _ in
                    onTermination()
                }

                do {
                    try process.run()
                    continuation.resume(returning: LaunchResult(
                        process: process,
                        commandHandle: inputPipe.fileHandleForWriting
                    ))
                } catch {
                    continuation.resume(throwing: MitmproxyServiceError.failedToRun(error.localizedDescription))
                }
            }
        }
    }

    nonisolated static func buildArguments(
        scriptURL: URL,
        selectedPort: Int,
        restrictToHosts: Bool,
        hosts: [String]
    ) -> [String] {
        var args: [String] = [
            "-p", "\(selectedPort)",
            "-s", scriptURL.path,
            "--set", "ssl_insecure=false",
            "--set", "connection_strategy=lazy"
        ]

        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["FRTM_UI_TEST_STORAGE"], !fixture.isEmpty {
            let directory = URL(fileURLWithPath: fixture, isDirectory: true).appending(path: "mitmproxy")
            args.append(contentsOf: ["--set", "confdir=\(directory.path)"])
        }
        #endif

        if restrictToHosts {
            let normalizedHosts = hosts.map { PinnedHost.normalized($0) }.filter { !$0.isEmpty }
            if normalizedHosts.isEmpty {
                args.append(contentsOf: ["--set", "ignore_hosts=.*"])
            } else {
                let allowRegexes = normalizedHosts.map(Self.hostAllowRegex(for:))
                for regex in allowRegexes {
                    args.append(contentsOf: ["--set", "allow_hosts=\(regex)"])
                }
            }
        }
        return args
    }

    private func bundledMitmdumpExecutableURL() throws -> URL {
        if let cachedMitmdumpURL {
            return cachedMitmdumpURL
        }
        
        guard let url = Bundle.main.resourceURL?.appending(path: "mitmproxy.app/Contents/MacOS/mitmdump") else {
            throw MitmproxyServiceError.executableNotFound("Resources/mitmproxy.app/Contents/MacOS/mitmdump")
        }
        
        try ensureExecutablePermission(for: url)
        cachedMitmdumpURL = url
        return url
    }
    
    private func ensureExecutablePermission(for url: URL) throws {
        let path = url.path
        let fileManager = FileManager.default
        
        if fileManager.isExecutableFile(atPath: path) {
            return
        }
        
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        
        guard fileManager.isExecutableFile(atPath: path) else {
            throw MitmproxyServiceError.failedToRun("Unable to make \(path) executable")
        }
    }

    /// Launches a lightweight `mitmdump --version` to force the bundled binary to unpack/cache itself before the user presses Start.
    private func schedulePrewarmMitmdumpExecutableIfNeeded() {
        guard prewarmTask == nil else { return }
        prewarmTask = Task(priority: .background) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.prewarmTask = nil
            guard !self.isRunning else { return }
            self.prewarmMitmdumpExecutableIfNeeded()
        }
    }

    private func prewarmMitmdumpExecutableIfNeeded() {
        guard warmupState == .idle else { return }
        warmupState = .warming
        
        do {
            let executableURL = try bundledMitmdumpExecutableURL()
            let warmupProcess = Process()
            warmupProcess.executableURL = executableURL
            warmupProcess.arguments = ["--version"]
            warmupProcess.standardOutput = Pipe()
            warmupProcess.standardError = Pipe()
            warmupProcess.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    guard let self else { return }
                    self.warmupProcess = nil
                    if proc.terminationStatus == 0 {
                        self.warmupState = .ready
                        self.onLog?("[PROXY] mitmdump ready to start\n")
                    } else {
                        self.warmupState = .failed("exited with code \(proc.terminationStatus)")
                        self.onLog?("[PROXY] mitmdump warmup failed (code \(proc.terminationStatus))\n")
                    }
                }
            }
            try warmupProcess.run()
            self.warmupProcess = warmupProcess
        } catch {
            warmupState = .failed(error.localizedDescription)
            onLog?("[PROXY] unable to pre-start mitmdump: \(error.localizedDescription)\n")
        }
    }
    
    private func bridgeScriptURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "py") else {
            throw MitmproxyServiceError.failedToRun("bridge.py not found in the bundle")
        }
        return url
    }

    private nonisolated static func hostAllowRegex(for host: String) -> String {
        // Matches the host itself and any subdomain of it.
        // NB: the leading group must reach mitmproxy as the regex `(^|\.)` —
        // i.e. start-of-string OR a literal dot. In a Swift literal that is
        // "(^|\\.)"; the previous "(^|\\\\.)" produced `(^|\\.)` (backslash +
        // any char), so the subdomain branch never matched a real dot.
        "(^|\\.)" + NSRegularExpression.escapedPattern(for: host) + "$"
    }
    
    private nonisolated func handleIncomingLine(_ line: String, launchID: UUID) {
        guard let data = line.data(using: .utf8) else { return }
        // Foundation delivers pipe frames off the UI thread. Decode there before
        // hopping to MainActor to publish state and notify persistence.
        let decoded = Self.decodeBridgeLine(data)
        Task { @MainActor [weak self] in
            guard let self, self.startupID == launchID else { return }
            self.handleBridgeLine(decoded, rawLine: line)
        }
    }

    enum DecodedBridgeLine {
        case ready(String?)
        case rules(RulesSyncEvent)
        case webSocket(WebSocketMessageEvent)
        case flow(MitmFlow)
        case captureMessage(String)
        case unknown
    }

    private struct BridgeEnvelope: Decodable {
        let event: String?
        let startup_id: String?
        let message: String?
    }

    nonisolated static func decodeBridgeLine(_ data: Data) -> DecodedBridgeLine {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(BridgeEnvelope.self, from: data) else { return .unknown }
        switch envelope.event {
        case "proxy_ready": return .ready(envelope.startup_id)
        case "rules_ack", "rules_error":
            guard let event = try? decoder.decode(RulesSyncEvent.self, from: data) else { return .unknown }
            return .rules(event)
        case "websocket_message":
            guard let event = try? decoder.decode(WebSocketMessageEvent.self, from: data) else { return .unknown }
            return .webSocket(event)
        case "capture_warning", "script_error": return .captureMessage(envelope.message ?? "Unknown error")
        default:
            guard let flow = try? decoder.decode(MitmFlow.self, from: data) else { return .unknown }
            return .flow(flow)
        }
    }

    private func handleBridgeLine(_ decoded: DecodedBridgeLine, rawLine: String) {
        switch decoded {
        case let .ready(id):
            if id == startupID.uuidString { bridgeReady = true }
        case let .rules(event):
            if event.revision == rulesRevision { rulesAckTask?.cancel(); rulesAckTask = nil }
            switch event.event {
            case .acknowledged:
                onLog?("[RULES] revision \(event.revision) applied (\(event.count ?? 0) rules)\n")
            case .failed:
                onLog?("[RULES] revision \(event.revision) rejected: \(event.message ?? "unknown error")\n")
            }
        case let .webSocket(event): appendWebSocketMessage(event)
        case let .flow(flow): mergeFlow(flow)
        case let .captureMessage(message): onLog?("[CAPTURE] \(message)\n")
        case .unknown: onLog?(rawLine)
        }
    }

    @MainActor
    private func appendWebSocketMessage(_ event: WebSocketMessageEvent) {
        var existing = flows[event.id] ?? MitmFlow(id: event.id, event: "websocket_message")
        if existing.request == nil {
            existing.livePreviewWarning = "This flow was evicted; its live preview may omit metadata or earlier frames. Use recorded sessions for the captured history."
        }
        existing.websocketMessages.append(event.websocketMessage)
        flowEventsSubject.send(existing)
        _ = LiveFlowMemoryBudget.trimWebSocket(&existing)
        cache(existing)

    }
    
    @MainActor
    private func mergeFlow(_ incoming: MitmFlow) {
        var updated = flows[incoming.id]?.mergingSessionSnapshot(with: incoming) ?? incoming
        if updated.requestTimestamp == nil, incoming.event == "request" {
            updated.requestTimestamp = incoming.timestamp
        }
        if updated.responseTimestamp == nil, incoming.event == "response" || incoming.event == "error" {
            updated.responseTimestamp = incoming.timestamp
        }
        cache(updated)
        // Persistence observes every event even when the flow cannot fit in the live cache.
        flowEventsSubject.send(updated)
    }

    private func cache(_ flow: MitmFlow) {
        let weight = LiveFlowMemoryBudget.cost(flow)
        retainedPayloadBytes += weight - (flowWeights[flow.id] ?? 0)
        flowWeights[flow.id] = weight
        flows[flow.id] = flow
        if flows.count > maxFlowsStored || retainedPayloadBytes > LiveFlowMemoryBudget.maximumBytes {
            flows = LiveFlowMemoryBudget.retain(flows, weights: flowWeights, maximumCount: maxFlowsStored)
            flowWeights = flowWeights.filter { flows[$0.key] != nil }
            retainedPayloadBytes = flowWeights.values.reduce(0, +)
            let now = ContinuousClock.now
            if lastCacheNotice == nil || now > (lastCacheNotice ?? now) + .seconds(5) {
                lastCacheNotice = now
                onLog?("[PERF] Live cache limited to 500 flows / 64 MiB payload; use recorded sessions for older flows\n")
            }
        }
    }

    func clearFlows() {
        flows.removeAll()
        flowWeights.removeAll()
        retainedPayloadBytes = 0
        lastCacheNotice = nil
        onLog?("[PROXY] Flussi puliti\n")
    }

    func stopProxy() {
        rulesAckTask?.cancel()
        rulesAckTask = nil
        startupID = UUID()
        bridgeReady = false
        isStarting = false
        if let proc = process, proc.isRunning { proc.terminate() }
        process = nil
        isRunning = false
        onLog?("mitmdump stopped\n")
        try? commandHandle?.close()
        commandHandle = nil
    }
    
    private func setupTerminationObservers() {
        appTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopProxy() }
        }
        
        workspaceTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopProxy() }
        }
    }
    
    func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?) {
        let payload: [String: Any] = [
            "type": "mock_response",
            "id": flowID,
            "body": body,
            "status": status ?? NSNull(),
            "headers": headers ?? NSNull()
        ]
        sendCommand(payload, successLog: "[MAP LOCAL] command sent for flow \(flowID) (\(body.count) bytes)\n")
    }
    
    func mockResponse(for flowID: String, body: String) {
        mockResponse(for: flowID, body: body, status: nil, headers: nil)
    }

    func applyTrafficProfile(_ profile: TrafficProfile) {
        let payload: [String: Any] = [
            "type": "traffic_profile",
            "profile": [
                "id": profile.id,
                "name": profile.name,
                "description": profile.description,
                "latency_ms": profile.latencyMs,
                "jitter_ms": profile.jitterMs,
                "downstream_kbps": profile.downstreamKbps,
                "upstream_kbps": profile.upstreamKbps,
                "packet_loss": profile.packetLoss,
                "response_delay_ms": profile.responseDelayMs
            ]
        ]

        sendCommand(payload, successLog: "[TRAFFIC] profile \(profile.name) activated\n")
    }
    
    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {
        let payload: [String: Any] = [
            "type": "mock_request",
            "id": flowID,
            "body": body,
            "headers": headers ?? NSNull()
        ]
        sendCommand(payload, successLog: "[MAP LOCAL] mock request sent for flow \(flowID)\n")
    }

    func mockRule(_ rule: MapRule) {
        let payload: [String: Any] = [
            "type": "mock_rule",
            "key": rule.key,
            "body": rule.body,
            "status": rule.status,
            "headers": rule.headers,
            "enabled": rule.isEnabled
        ]

        sendCommand(payload, successLog: "[MAP LOCAL] rule updated for \(rule.key)\n")
    }

    func replaceRules(_ document: TrafficRuleDocument) {
        guard let documentData = try? JSONEncoder().encode(document),
              let documentObject = try? JSONSerialization.jsonObject(with: documentData) as? [String: Any]
        else {
            onLog?("[RULES] unable to encode rule document\n")
            return
        }
        rulesRevision += 1
        let payload: [String: Any] = [
            "type": "replace_rules",
            "revision": rulesRevision,
            "document": documentObject
        ]
        sendCommand(payload, successLog: "[RULES] revision \(rulesRevision) sent\n")
        rulesAckTask?.cancel()
        let revision = rulesRevision
        rulesAckTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.onLog?("[RULES] revision \(revision) was not acknowledged; rules may not be active\n")
        }
    }

    func deleteRule(forKey key: String) {
        let payload: [String: Any] = [
            "type": "delete_rule",
            "key": key
        ]

        sendCommand(payload, successLog: "[MAP LOCAL] rule removed for \(key)\n")
    }
    
    func updateBreakpointRule(_ rule: FlowBreakpointRule) {
        let payload: [String: Any] = [
            "type": "breakpoint_rule",
            "key": rule.key,
            "request": rule.interceptRequest,
            "response": rule.interceptResponse
        ]
        sendCommand(payload, successLog: "[BREAKPOINT] rule updated for \(rule.key)\n")
    }

    func deleteBreakpointRule(forKey key: String) {
        let payload: [String: Any] = [
            "type": "breakpoint_rule",
            "key": key,
            "request": false,
            "response": false
        ]
        sendCommand(payload, successLog: "[BREAKPOINT] rule removed for \(key)\n")
    }

    private func sendCommand(_ payload: [String: Any], successLog: String) {
        guard var data = try? JSONSerialization.data(withJSONObject: payload),
              let handle = commandHandle else {
            onLog?("[PROXY CMD] unable to send command: invalid handle or JSON\n")
            return
        }

        data.append(0x0A) // newline terminator
        commandWriteQueue.async { [weak self] in
            do {
                try handle.write(contentsOf: data)
            } catch {
                Task { @MainActor [weak self] in
                    self?.onLog?("[PROXY CMD] write failed: \(error.localizedDescription)\n")
                }
            }
        }
        onLog?(successLog)
    }

    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String]) {
        let payload: [String: Any] = [
            "type": "retry_flow",
            "id": flowID,
            "method": method,
            "url": url,
            "body": body ?? "",
            "headers": headers
        ]
        sendCommand(payload, successLog: "[RETRY] request resent for flow \(flowID)\n")
    }

    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {
        var payload: [String: Any] = [
            "type": "breakpoint_continue",
            "id": flowID,
            "phase": phase.rawValue
        ]

        if let requestPayload {
            payload["request"] = [
                "method": requestPayload.method,
                "url": requestPayload.url,
                "headers": requestPayload.headers,
                "body": requestPayload.body ?? ""
            ]
        }

        if let responsePayload {
            payload["response"] = [
                "status": responsePayload.status,
                "headers": responsePayload.headers,
                "body": responsePayload.body
            ]
        }

        sendCommand(payload, successLog: "[BREAKPOINT] resume inviato per \(flowID) (\(phase.rawValue))\n")
    }
}
