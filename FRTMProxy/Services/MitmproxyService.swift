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
    case failedToRun(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToRun(let reason):
            return "Unable to run Swift Proxy Engine: \(reason)"
        }
    }
}

@MainActor
final class MitmproxyService: ObservableObject, ProxyServiceProtocol {
    private let config: MitmproxyConfig
    private let engine = SwiftProxyEngine()
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
            self.setupEngineCallbacks()
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
    
    private func setupEngineCallbacks() {
        engine.onLog = { [weak self] message in
            self?.onLog?(message)
        }
        engine.onFlowUpdate = { [weak self] flow in
            self?.mergeFlow(flow)
        }
    }
    
    func startProxy(port: Int? = nil, restrictToHosts: Bool = false, hosts: [String] = []) async throws {
        if isRunning {
            return
        }
        
        let selectedPort = port ?? config.port
        
        do {
            try engine.start(port: selectedPort, restrictToHosts: restrictToHosts, allowedHosts: hosts)
            self.isRunning = true
            onLog?("Swift Proxy started on port \(selectedPort)\n")
        } catch {
            throw MitmproxyServiceError.failedToRun(error.localizedDescription)
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
        engine.stop()
        isRunning = false
        onLog?("Swift Proxy stopped\n")
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
        // Find existing flow to get its host/path if needed, or just use a dummy key
        if let flow = flows[flowID], let request = flow.request {
            let url = URL(string: request.url)
            let host = url?.host ?? ""
            let path = url?.path ?? ""
            let key = "\(host)\(path)"

            let rule = MapRule(
                key: key,
                host: host,
                path: path,
                body: body,
                status: status ?? 200,
                headers: headers ?? [:]
            )
            engine.updateMapRule(rule)
            onLog?("[MAP LOCAL] mock response applied for \(key)\n")
        }
    }
    
    func mockResponse(for flowID: String, body: String) {
        mockResponse(for: flowID, body: body, status: nil, headers: nil)
    }

    func applyTrafficProfile(_ profile: TrafficProfile) {
        engine.setTrafficProfile(profile)
        onLog?("[TRAFFIC] profile \(profile.name) activated\n")
    }
    
    func mockRequest(for flowID: String, body: String, headers: [String: String]?) {
        // Not directly supported in the same way as mitmproxy, but we can simulate it by updating the flow
        if var flow = flows[flowID], var request = flow.request {
            // This is mostly for UI/History in our native engine
            flow.request = MitmFlow.Request(method: request.method, url: request.url, headers: headers ?? request.headers, body: body)
            flows[flowID] = flow
            onLog?("[PROXY] flow \(flowID) request updated in memory\n")
        }
    }

    func mockRule(_ rule: MapRule) {
        engine.updateMapRule(rule)
        onLog?("[MAP LOCAL] rule updated for \(rule.key)\n")
    }

    func deleteRule(forKey key: String) {
        engine.deleteMapRule(forKey: key)
        onLog?("[MAP LOCAL] rule removed for \(key)\n")
    }
    
    func updateBreakpointRule(_ rule: FlowBreakpointRule) {
        engine.updateBreakpointRule(rule)
        onLog?("[BREAKPOINT] rule updated for \(rule.key)\n")
    }

    func deleteBreakpointRule(forKey key: String) {
        engine.deleteBreakpointRule(forKey: key)
        onLog?("[BREAKPOINT] rule removed for \(key)\n")
    }

    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String]) {
        let bodyData = body?.data(using: .utf8) ?? Data()
        engine.retryFlow(method: method, url: url, headers: headers, body: bodyData)
        onLog?("[RETRY] retry initiated for \(url)\n")
    }

    func resumeBreakpoint(
        flowID: String,
        phase: FlowBreakpointPhase,
        requestPayload: BreakpointRequestPayload?,
        responsePayload: BreakpointResponsePayload?
    ) {
        let payload = BreakpointResumePayload(request: requestPayload, response: responsePayload)
        engine.resumeBreakpoint(flowID: flowID, payload: payload)
        onLog?("[BREAKPOINT] resume inviato per \(flowID) (\(phase.rawValue))\n")
    }
}
