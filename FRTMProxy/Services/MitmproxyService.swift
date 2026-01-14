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
            return "Eseguibile mitmdump non trovato a: \(path)"
        case .failedToRun(let reason):
            return "Impossibile eseguire mitmdump: \(reason)"
        }
    }
}

@MainActor
final class MitmproxyService: ObservableObject, ProxyServiceProtocol {
    private let config: MitmproxyConfig
    private var process: Process?
    private var commandHandle: FileHandle?
    private let maxFlowsStored = 500
    private var appTerminationObserver: NSObjectProtocol?
    private var workspaceTerminationObserver: NSObjectProtocol?
    
    nonisolated(unsafe) var onLog: ((String) -> Void)?
    
    /// Proxy running?
    @Published private(set) var isRunning: Bool = false
    @Published var flows: [String: MitmFlow] = [:]

    var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { $flows.eraseToAnyPublisher() }
    var isRunningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }
    
    nonisolated init(config: MitmproxyConfig) {
        self.config = config
        Task { @MainActor in
            self.setupTerminationObservers()
        }
    }
    
    deinit {
        if let observer = appTerminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = workspaceTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        Task { @MainActor [weak self]  in
            self?.stopProxy()
        }
    }
    
    func startProxy(port: Int? = nil, restrictToHosts: Bool = false, hosts: [String] = []) throws {
        if isRunning {
            return
        }

        terminateStaleMitmProcesses()
        
        let executableURL = try bundledMitmdumpExecutableURL()
        let scriptURL = try bridgeScriptURL()
        let selectedPort = port ?? config.port
        
        let process = Process()
        process.executableURL = executableURL
        var args: [String] = [
            "-p", "\(selectedPort)",
            "-s", scriptURL.path,
            "--anticache",
            "--set", "connection_strategy=lazy",
            "--set", "ssl_insecure=true"
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
        process.arguments = args
        
        print("VALELOG process url \(process.executableURL)")
        
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        var stdoutBuffer = Data()

        process.standardOutput = pipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        commandHandle = inputPipe.fileHandleForWriting

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            stdoutBuffer.append(handle.availableData)

            // Process complete lines; keep leftovers in the buffer
            while let range = stdoutBuffer.firstRange(of: Data([0x0A])) {
                let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...range.lowerBound)
                if let text = String(data: lineData, encoding: .utf8), !text.isEmpty {
                    self.handleIncomingLine(text)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self?.onLog?("[ERR] " + text)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
        
        do {
            try process.run()
            self.process = process
            self.isRunning = true
            onLog?("mitmdump started on port \(selectedPort)\n")
        } catch {
            throw MitmproxyServiceError.failedToRun(error.localizedDescription)
        }
    }
    
    private func terminateStaleMitmProcesses() {
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
                    onLog?("[PROXY] terminated stale mitm processes via \(command.path)\n")
                    break
                }
            } catch {
                continue
            }
        }
    }
    
    private func bundledMitmdumpExecutableURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "mitmdump", withExtension: nil) else {
            print("NOT FOUND")
            throw MitmproxyServiceError.executableNotFound("Resources/mitmdump")
        }
        
        try ensureExecutablePermission(for: url)
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
            throw MitmproxyServiceError.failedToRun("Impossibile rendere eseguibile \(path)")
        }
    }
    
    private func bridgeScriptURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "py") else {
            throw MitmproxyServiceError.failedToRun("bridge.py non trovato nel bundle")
        }
        return url
    }

    private static func hostAllowRegex(for host: String) -> String {
        // Matches the host itself and any subdomain of it.
        "(^|\\\\.)" + NSRegularExpression.escapedPattern(for: host) + "$"
    }
    
    private nonisolated func handleIncomingLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let genericMessage = try JSONDecoder().decode(GenericMessage.self, from: data)
            DispatchQueue.main.async {
                switch genericMessage.event {
                case "websocket_message":
                    do {
                        let wsMessage = try JSONDecoder().decode(WebSocketMessageWrapper.self, from: data)
                        if var flow = self.flows[wsMessage.id] {
                            flow.webSocketMessages.append(wsMessage.message)
                            self.flows[wsMessage.id] = flow
                        }
                    } catch {
                        self.onLog?("[DECODE ERR] WebSocket: \(error.localizedDescription)")
                    }
                case "grpc_message":
                    do {
                        let grpcMessage = try JSONDecoder().decode(GRPCMessageWrapper.self, from: data)
                        if var flow = self.flows[grpcMessage.id] {
                            flow.grpcMessages.append(grpcMessage.message)
                            self.flows[grpcMessage.id] = flow
                        }
                    } catch {
                        self.onLog?("[DECODE ERR] gRPC: \(error.localizedDescription)")
                    }
                default:
                    do {
                        let flow = try JSONDecoder().decode(MitmFlow.self, from: data)
                        self.mergeFlow(flow)
                    } catch {
                        self.onLog?(line)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.onLog?(line)
            }
        }
    }
    
    @MainActor
    private func mergeFlow(_ incoming: MitmFlow) {
        if var existing = flows[incoming.id] {
            if incoming.event == "request" {
                existing.request = incoming.request
            }
            if incoming.event == "response" {
                existing.response = incoming.response
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
            flows[incoming.id] = incoming
        }

        if flows.count > maxFlowsStored {
            trimOldFlows()
        }
    }

    private func trimOldFlows() {
        let ordered = flows.values.sorted { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
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
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let handle = commandHandle else {
            onLog?("[PROXY CMD] impossibile inviare comando: handle o JSON non valido\n")
            return
        }

        handle.write(data)
        handle.write(Data([0x0A])) // newline terminator
        onLog?("[MAP LOCAL] comando inviato per flow \(flowID) (\(body.count) byte)\n")
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
                "packet_loss": profile.packetLoss
            ]
        ]

        sendCommand(payload, successLog: "[TRAFFIC] profilo \(profile.name) attivato\n")
    }
    
    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {
        let payload: [String: Any] = [
            "type": "mock_request",
            "id": flowID,
            "body": body,
            "headers": headers ?? NSNull()
        ]
        sendCommand(payload, successLog: "[MAP LOCAL] richiesta mock inviata per flow \(flowID)\n")
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

        sendCommand(payload, successLog: "[MAP LOCAL] regola aggiornata per \(rule.key)\n")
    }

    func deleteRule(forKey key: String) {
        let payload: [String: Any] = [
            "type": "delete_rule",
            "key": key
        ]

        sendCommand(payload, successLog: "[MAP LOCAL] regola rimossa per \(key)\n")
    }
    
    func updateBreakpointRule(_ rule: FlowBreakpointRule) {
        let payload: [String: Any] = [
            "type": "breakpoint_rule",
            "key": rule.key,
            "request": rule.interceptRequest,
            "response": rule.interceptResponse
        ]
        sendCommand(payload, successLog: "[BREAKPOINT] regola aggiornata per \(rule.key)\n")
    }

    func deleteBreakpointRule(forKey key: String) {
        let payload: [String: Any] = [
            "type": "breakpoint_rule",
            "key": key,
            "request": false,
            "response": false
        ]
        sendCommand(payload, successLog: "[BREAKPOINT] regola rimossa per \(key)\n")
    }

    private func sendCommand(_ payload: [String: Any], successLog: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let handle = commandHandle else {
            onLog?("[PROXY CMD] impossibile inviare comando: handle o JSON non valido\n")
            return
        }

        handle.write(data)
        handle.write(Data([0x0A]))
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
        sendCommand(payload, successLog: "[RETRY] richiesta reinviata per flow \(flowID)\n")
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
