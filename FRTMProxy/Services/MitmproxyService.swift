import Foundation
import Combine
import AppKit
import CoreData

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
    private var appTerminationObserver: NSObjectProtocol?
    private var workspaceTerminationObserver: NSObjectProtocol?
    private let context: NSManagedObjectContext
    
    nonisolated(unsafe) var onLog: ((String) -> Void)?
    
    /// Proxy running?
    @Published private(set) var isRunning: Bool = false

    var isRunningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }
    
    nonisolated init(config: MitmproxyConfig) {
        self.config = config
        let persistenceController = PersistenceController.shared
        self.context = persistenceController.container.newBackgroundContext()
        self.context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

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

        pruneOldFlows()
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
    
    private func pruneOldFlows() {
        context.perform {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CDFlow.fetchRequest()

            // Prune flows older than 7 days
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            fetchRequest.predicate = NSPredicate(format: "timestamp < %@", sevenDaysAgo as NSDate)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try self.context.execute(deleteRequest)
                try self.context.save()
                DispatchQueue.main.async {
                    self.onLog?("[DB] Pruned old flows.\n")
                }
            } catch {
                DispatchQueue.main.async {
                    self.onLog?("[DB ERR] Failed to prune old flows: \(error.localizedDescription)\n")
                }
            }
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

        if let flow = try? JSONDecoder().decode(MitmFlow.self, from: data) {
            mergeFlow(flow)
        } else {
            DispatchQueue.main.async {
                self.onLog?(line)
            }
        }
    }

    private func mergeFlow(_ incoming: MitmFlow) {
        context.perform {
            let fetchRequest: NSFetchRequest<CDFlow> = CDFlow.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", incoming.id)

            do {
                let results = try self.context.fetch(fetchRequest)
                let cdFlow = results.first ?? CDFlow(context: self.context)

                // Update CDFlow attributes
                cdFlow.id = incoming.id
                cdFlow.event = incoming.event
                if let timestamp = incoming.timestamp {
                    cdFlow.timestamp = Date(timeIntervalSince1970: timestamp)
                }

                if let breakpoint = incoming.breakpoint {
                    cdFlow.breakpointState = breakpoint.state.rawValue
                    cdFlow.breakpointPhase = breakpoint.phase.rawValue
                    cdFlow.breakpointKey = breakpoint.key
                } else {
                    cdFlow.breakpointState = nil
                    cdFlow.breakpointPhase = nil
                    cdFlow.breakpointKey = nil
                }

                if let requestData = incoming.request {
                    let cdRequest = cdFlow.request ?? CDRequest(context: self.context)
                    cdRequest.method = requestData.method
                    cdRequest.url = requestData.url
                    cdRequest.headers = requestData.headers as NSObject
                    cdRequest.body = requestData.body
                    cdFlow.request = cdRequest
                }

                if let responseData = incoming.response {
                    let cdResponse = cdFlow.response ?? CDResponse(context: self.context)
                    cdResponse.status = Int32(responseData.status ?? 0)
                    cdResponse.headers = responseData.headers as NSObject
                    cdResponse.body = responseData.body
                    cdFlow.response = cdResponse
                }

                if let clientData = incoming.client {
                    let cdClient = cdFlow.client ?? CDClient(context: self.context)
                    cdClient.ip = clientData.ip
                    cdClient.port = Int32(clientData.port ?? 0)
                    cdFlow.client = cdClient
                }

                if self.context.hasChanges {
                    try self.context.save()
                }
            } catch {
                DispatchQueue.main.async {
                    self.onLog?("[CoreData ERR] Failed to save flow: \(error.localizedDescription)\n")
                }
            }
        }
    }

    func clearFlows() {
        context.perform {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CDFlow.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try self.context.execute(deleteRequest)
                try self.context.save()
                DispatchQueue.main.async {
                    self.onLog?("[PROXY] Flows cleared from database\n")
                }
            } catch {
                DispatchQueue.main.async {
                    self.onLog?("[CoreData ERR] Failed to clear flows: \(error.localizedDescription)\n")
                }
            }
        }
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
