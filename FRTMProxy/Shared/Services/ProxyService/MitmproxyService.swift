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
    private var appTerminationObserver: NSObjectProtocol?
    private var workspaceTerminationObserver: NSObjectProtocol?
    private var warmupState: MitmdumpWarmupState = .idle
    private var warmupProcess: Process?
    private var prewarmTask: Task<Void, Never>?
    private var cachedMitmdumpURL: URL?
    private var rulesRevision = 0
    /// Serializza le scritture su stdin del bridge fuori dal MainActor: una
    /// pipe piena bloccherebbe la UI, e la write può fallire (EPIPE) se il
    /// processo è morto — qui viene gestita senza bloccare né crashare.
    private let commandWriteQueue = DispatchQueue(label: "com.frtmproxy.command-write", qos: .userInitiated)
    
    nonisolated(unsafe) var onLog: ((String) -> Void)?
    
    /// Proxy running?
    @Published private(set) var isRunning: Bool = false
    @Published var flows: [String: MitmFlow] = [:]
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
        if isRunning {
            return
        }
        
        let executableURL = try bundledMitmdumpExecutableURL()
        let scriptURL = try bridgeScriptURL()
        let selectedPort = port ?? config.port
        let logger = onLog

        let result = try await MitmproxyService.launchProcess(
            executableURL: executableURL,
            scriptURL: scriptURL,
            selectedPort: selectedPort,
            restrictToHosts: restrictToHosts,
            hosts: hosts,
            onLine: { [weak self] line in
                self?.handleIncomingLine(line)
            },
            onError: { [weak self] text in
                self?.onLog?("[ERR] " + text)
            },
            onTermination: { [weak self] in
                DispatchQueue.main.async {
                    self?.isRunning = false
                }
            },
            logger: logger
        )

        self.process = result.process
        self.commandHandle = result.commandHandle
        self.isRunning = true
        onLog?("mitmdump started on port \(selectedPort)\n")
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
        onLine: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onTermination: @escaping () -> Void,
        logger: ((String) -> Void)?
    ) async throws -> LaunchResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                MitmproxyService.terminateStaleMitmProcesses(logger: logger)

                let process = Process()
                process.executableURL = executableURL
                process.arguments = MitmproxyService.buildArguments(
                    scriptURL: scriptURL,
                    selectedPort: selectedPort,
                    restrictToHosts: restrictToHosts,
                    hosts: hosts
                )

                let pipe = Pipe()
                let errorPipe = Pipe()
                let inputPipe = Pipe()
                let stdoutLineBuffer = LineBuffer(onLine: onLine)

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

    private static func buildArguments(
        scriptURL: URL,
        selectedPort: Int,
        restrictToHosts: Bool,
        hosts: [String]
    ) -> [String] {
        var args: [String] = [
            "-p", "\(selectedPort)",
            "-s", scriptURL.path,
            "--set", "ssl_insecure=true",
            "--set", "connection_strategy=lazy"
        ]

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

    private static func terminateStaleMitmProcesses(logger: ((String) -> Void)?) {
        let commands: [(path: String, args: [String])] = [
            ("/usr/bin/pkill", ["-TERM", "-f", "mitmdump"]),
            ("/usr/bin/pkill", ["-TERM", "-f", "mitmproxy"]),
            ("/usr/bin/killall", ["mitmdump"])
        ]

        for command in commands {
            guard FileManager.default.isExecutableFile(atPath: command.path) else { continue }
            let killer = Process()
            killer.executableURL = URL(fileURLWithPath: command.path)
            killer.arguments = command.args
            killer.standardOutput = Pipe()
            killer.standardError = Pipe()
            do {
                try killer.run()
                killer.waitUntilExit()
                if killer.terminationStatus == 0 {
                    logger?("[PROXY] terminated stale mitm processes via \(command.path)\n")
                    break
                }
            } catch {
                continue
            }
        }
    }
    
    private func bundledMitmdumpExecutableURL() throws -> URL {
        if let cachedMitmdumpURL {
            return cachedMitmdumpURL
        }
        
        guard let url = Bundle.main.url(forResource: "mitmdump", withExtension: nil) else {
            throw MitmproxyServiceError.executableNotFound("Resources/mitmdump")
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

    private static func hostAllowRegex(for host: String) -> String {
        // Matches the host itself and any subdomain of it.
        // NB: the leading group must reach mitmproxy as the regex `(^|\.)` —
        // i.e. start-of-string OR a literal dot. In a Swift literal that is
        // "(^|\\.)"; the previous "(^|\\\\.)" produced `(^|\\.)` (backslash +
        // any char), so the subdomain branch never matched a real dot.
        "(^|\\.)" + NSRegularExpression.escapedPattern(for: host) + "$"
    }
    
    private nonisolated func handleIncomingLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if let rulesEvent = try? JSONDecoder().decode(RulesSyncEvent.self, from: data) {
            DispatchQueue.main.async {
                switch rulesEvent.event {
                case .acknowledged:
                    self.onLog?("[RULES] revision \(rulesEvent.revision) applied (\(rulesEvent.count ?? 0) rules)\n")
                case .failed:
                    self.onLog?("[RULES] revision \(rulesEvent.revision) rejected: \(rulesEvent.message ?? "unknown error")\n")
                }
            }
            return
        }

        // WebSocket message events are decoded separately to avoid polluting MitmFlow.
        if let wsEvent = try? JSONDecoder().decode(WebSocketMessageEvent.self, from: data),
           wsEvent.event == "websocket_message" {
            DispatchQueue.main.async {
                self.appendWebSocketMessage(wsEvent)
            }
            return
        }

        if let flow = try? JSONDecoder().decode(MitmFlow.self, from: data) {
            DispatchQueue.main.async {
                self.mergeFlow(flow)
            }
        } else {
            DispatchQueue.main.async {
                self.onLog?(line)
            }
        }
    }

    @MainActor
    private func appendWebSocketMessage(_ event: WebSocketMessageEvent) {
        guard var existing = flows[event.id] else { return }
        existing.websocketMessages.append(event.websocketMessage)
        flows[event.id] = existing
        flowEventsSubject.send(existing)
    }
    
    @MainActor
    private func mergeFlow(_ incoming: MitmFlow) {
        if var existing = flows[incoming.id] {
            if incoming.event == "request" {
                existing.request = incoming.request
                if let timestamp = incoming.timestamp {
                    existing.requestTimestamp = timestamp
                }
            }
            if incoming.event == "response" {
                existing.response = incoming.response
                if let timestamp = incoming.timestamp {
                    existing.responseTimestamp = timestamp
                }
            }
            if let breakpoint = incoming.breakpoint {
                existing.breakpoint = breakpoint
            } else if existing.breakpoint != nil && incoming.breakpoint == nil {
                existing.breakpoint = nil
            }
            if existing.timestamp == nil {
                existing.timestamp = incoming.timestamp
            }
            flows[incoming.id] = existing
        } else {
            var created = incoming
            if created.requestTimestamp == nil, created.event == "request" {
                created.requestTimestamp = created.timestamp
            }
            if created.responseTimestamp == nil, created.event == "response" {
                created.responseTimestamp = created.timestamp
            }
            flows[incoming.id] = created
        }

        if flows.count > maxFlowsStored {
            trimOldFlows()
        }
        if let merged = flows[incoming.id] {
            flowEventsSubject.send(merged)
        }
    }

    private func trimOldFlows() {
        // Ordina per attività più recente: il merge aggiorna request/response
        // timestamp ma non `timestamp` (che resta quello della prima comparsa),
        // quindi usarlo qui poterebbe flussi con attività recente.
        func lastActivity(_ flow: MitmFlow) -> TimeInterval {
            flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp ?? 0
        }
        let ordered = flows.values.sorted { lastActivity($0) > lastActivity($1) }
        let trimmed = ordered.prefix(maxFlowsStored)
        var newDict: [String: MitmFlow] = [:]
        trimmed.forEach { newDict[$0.id] = $0 }
        flows = newDict
        onLog?("[PERF] Flussi limitati a \(maxFlowsStored) per evitare uso eccessivo di memoria/cpu\n")
    }

    func clearFlows() {
        flows.removeAll()
        onLog?("[PROXY] Flussi puliti\n")
    }

    func stopProxy() {
        guard let proc = process else { return }
        proc.terminate()
        process = nil
        isRunning = false
        onLog?("mitmdump stopped\n")
        commandHandle = nil
    }
    
    private func setupTerminationObservers() {
        appTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.stopProxy()
        }
        
        workspaceTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.stopProxy()
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
                DispatchQueue.main.async {
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
