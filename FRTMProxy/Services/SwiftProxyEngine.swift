import Foundation
import Network
import CryptoKit
import Combine
import Security

enum ProxyError: Error {
    case invalidRequest
    case connectionFailed(String)
}

struct ProxyState {
    var mapRules: [String: MapRule] = [:]
    var breakpointRules: [String: FlowBreakpointRule] = [:]
    var trafficProfile: TrafficProfile?
    var restrictToHosts: Bool = false
    var allowedHosts: [String] = []
}

struct BreakpointResumePayload {
    let request: BreakpointRequestPayload?
    let response: BreakpointResponsePayload?
}

enum TrafficDirection {
    case uplink
    case downlink
}

@MainActor
final class SwiftProxyEngine {
    private var continuations: [String: CheckedContinuation<BreakpointResumePayload?, Never>] = [:]
    private var listener: NWListener?
    private var tlsListener: NWListener?
    private(set) var tlsPort: Int = 0
    private(set) var state = ProxyState()
    private var connections: [UUID: ProxyConnection] = [:]

    var onFlowUpdate: ((MitmFlow) -> Void)?
    var onLog: ((String) -> Void)?

    func start(port: Int, restrictToHosts: Bool, allowedHosts: [String]) throws {
        self.state.restrictToHosts = restrictToHosts
        self.state.allowedHosts = allowedHosts

        try startTLSListener()

        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!

        listener = try NWListener(using: parameters, on: nwPort)
        listener?.newConnectionHandler = { [weak self] nwConnection in
            Task { @MainActor in self?.handleNewConnection(nwConnection) }
        }
        listener?.start(queue: .main)
        onLog?("Swift Proxy Engine ready on port \(port)\n")
    }

    private func startTLSListener() throws {
        let tlsParams = NWParameters.tcp
        let tlsOptions = NWProtocolOptions.tls

        sec_protocol_options_set_selection_handler(tlsOptions.securityProtocolOptions, { (options, completion) in
            let serverName = sec_protocol_metadata_get_server_name(options).map { String(cString: $0) }
            let host = serverName ?? "unknown.host"

            DispatchQueue.global().async {
                do {
                    let identity = try CertificateManager.shared.identity(for: host)
                    let secIdentity = sec_identity_create(identity)!
                    sec_protocol_options_set_local_identity(options, secIdentity)
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }, .main)

        tlsParams.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)

        tlsListener = try NWListener(using: tlsParams, on: .any)
        tlsListener?.newConnectionHandler = { [weak self] nwConnection in
            Task { @MainActor in self?.handleDecryptedConnection(nwConnection) }
        }
        tlsListener?.start(queue: .main)
        tlsPort = Int(tlsListener?.port?.rawValue ?? 0)
        onLog?("Internal TLS Listener ready on port \(tlsPort)\n")
    }

    func stop() {
        listener?.cancel()
        tlsListener?.cancel()
        for conn in connections.values { conn.cancel() }
        connections.removeAll()
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = ProxyConnection(nwConnection: nwConnection, engine: self)
        connections[connection.id] = connection
        connection.onClose = { [weak self, id = connection.id] in
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        }
        connection.start()
    }

    private func handleDecryptedConnection(_ nwConnection: NWConnection) {
        let connection = ProxyConnection(nwConnection: nwConnection, engine: self, isDecrypted: true)
        connections[connection.id] = connection
        connection.onClose = { [weak self, id = connection.id] in
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        }
        connection.start()
    }

    func updateMapRule(_ rule: MapRule) { state.mapRules[rule.key] = rule }
    func deleteMapRule(forKey key: String) { state.mapRules.removeValue(forKey: key) }
    func updateBreakpointRule(_ rule: FlowBreakpointRule) { state.breakpointRules[rule.key] = rule }
    func deleteBreakpointRule(forKey key: String) { state.breakpointRules.removeValue(forKey: key) }
    func setTrafficProfile(_ profile: TrafficProfile) { state.trafficProfile = profile }

    func notifyFlowUpdate(_ flow: MitmFlow) { onFlowUpdate?(flow) }

    func findBreakpointRule(for url: URL) -> FlowBreakpointRule? {
        let host = url.host ?? ""
        let path = url.path
        let key = "\(host)\(path)"
        if let rule = state.breakpointRules[key], rule.isEnabled { return rule }
        for rule in state.breakpointRules.values where rule.isEnabled {
            if matchWildcard(pattern: rule.key, string: key) { return rule }
        }
        return nil
    }

    func waitForBreakpoint(flowID: String, phase: FlowBreakpointPhase, key: String) async -> BreakpointResumePayload? {
        let flow = MitmFlow(id: flowID, event: "request", breakpoint: FlowBreakpointMetadata(phase: phase, state: .waiting, key: key))
        notifyFlowUpdate(flow)
        return await withCheckedContinuation { continuation in
            continuations[flowID] = continuation
        }
    }

    func resumeBreakpoint(flowID: String, payload: BreakpointResumePayload?) {
        continuations.removeValue(forKey: flowID)?.resume(returning: payload)
    }

    func applyTrafficProfile(direction: TrafficDirection, bodySize: Int) async throws {
        guard let profile = state.trafficProfile, profile.id != "traffic.off" else { return }
        let baseLatency = Double(profile.latencyMs) / 1000.0
        let jitter = Double(profile.jitterMs) / 1000.0
        let totalLatency = baseLatency + (jitter > 0 ? Double.random(in: -jitter...jitter) : 0)
        if totalLatency > 0 { try? await Task.sleep(for: .seconds(totalLatency)) }
        if direction == .downlink && profile.packetLoss > 0 {
            if Double.random(in: 0...1) < profile.packetLoss { throw ProxyError.connectionFailed("Simulated packet loss") }
        }
        let kbps = direction == .uplink ? profile.upstreamKbps : profile.downstreamKbps
        if kbps > 0 {
            let bwDelay = Double(bodySize) / (Double(kbps) * 125.0)
            if bwDelay > 0 { try? await Task.sleep(for: .seconds(bwDelay)) }
        }
    }

    func findMapRule(for method: String, url: URL) -> MapRule? {
        let host = url.host ?? ""
        let path = url.path
        let key = "\(host)\(path)"
        if let rule = state.mapRules[key], rule.isEnabled { return rule }
        for rule in state.mapRules.values where rule.isEnabled {
            if matchWildcard(pattern: rule.key, string: key) { return rule }
        }
        return nil
    }

    private func matchWildcard(pattern: String, string: String) -> Bool {
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: "^\(escapedPattern)$") else { return false }
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
    }

    func retryFlow(method: String, url: String, headers: [String: String], body: Data) {
        Task {
            // We create a dummy connection context for the retry
            let dummyConnection = ProxyConnection(nwConnection: NWConnection(to: .hostPort(host: "127.0.0.1", port: 0), using: .tcp), engine: self)
            await dummyConnection.handleRegularRequest(method: method, url: url, headers: headers, body: body)
        }
    }

    func log(_ message: String) { onLog?(message) }
}

class ProxyConnection: Identifiable {
    let id = UUID()
    let nwConnection: NWConnection
    unowned let engine: SwiftProxyEngine
    var onClose: (() -> Void)?
    private let isDecrypted: Bool
    private var buffer = Data()

    init(nwConnection: NWConnection, engine: SwiftProxyEngine, isDecrypted: Bool = false) {
        self.nwConnection = nwConnection
        self.engine = engine
        self.isDecrypted = isDecrypted
    }

    func start() {
        nwConnection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.onClose?() }
            if case .cancelled = state { self?.onClose?() }
        }
        nwConnection.start(queue: .main)
        receiveNext()
    }

    func cancel() { nwConnection.cancel() }

    private func receiveNext() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data { self?.handleData(data) }
            if isComplete || error != nil { self?.cancel() } else { self?.receiveNext() }
        }
    }

    private func handleData(_ data: Data) {
        buffer.append(data)
        if let range = buffer.firstRange(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
            let headerData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            let remaining = buffer.subdata(in: range.upperBound..<buffer.endIndex)
            buffer.removeAll()
            if let headers = String(data: headerData, encoding: .utf8) {
                Task { await parseAndProcessRequest(headerString: headers, body: remaining) }
            }
        }
    }

    private func parseAndProcessRequest(headerString: String, body: Data) async {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 3 else { return }
        let method = parts[0], urlString = parts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let p = line.components(separatedBy: ": ")
            if p.count == 2 { headers[p[0]] = p[1] }
        }

        if method == "CONNECT" {
            handleConnect(host: urlString)
        } else {
            var finalURL = urlString
            if !finalURL.contains("://") {
                let scheme = isDecrypted ? "https" : "http"
                finalURL = "\(scheme)://\(headers["Host"] ?? "")\(finalURL)"
            }
            await handleRegularRequest(method: method, url: finalURL, headers: headers, body: body)
        }
    }

    private func handleConnect(host: String) {
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
        nwConnection.send(content: response.data(using: .utf8), completion: .contentProcessed({ [weak self] _ in
            guard let self = self else { return }
            let localConn = NWConnection(to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(self.engine.tlsPort))!), using: .tcp)
            localConn.stateUpdateHandler = { state in
                if case .ready = state { self.splice(self.nwConnection, localConn) }
            }
            localConn.start(queue: .main)
        }))
    }

    private func splice(_ a: NWConnection, _ b: NWConnection) {
        a.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            if let data = data { b.send(content: data, completion: .contentProcessed({ _ in })) }
            if !isComplete { self.splice(a, b) }
        }
        b.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            if let data = data { a.send(content: data, completion: .contentProcessed({ _ in })) }
            if !isComplete { self.splice(b, a) }
        }
    }

    private func handleRegularRequest(method: String, url: String, headers: [String: String], body: Data) async {
        guard let requestURL = URL(string: url), let host = requestURL.host else { return }
        let flowID = UUID().uuidString
        var curM = method, curU = url, curH = headers, curB = body
        if let bp = await engine.findBreakpointRule(for: requestURL), bp.interceptRequest {
            if let res = await engine.waitForBreakpoint(flowID: flowID, phase: .request, key: bp.key) {
                if let r = res.request { curM = r.method; curU = r.url; curH = r.headers; curB = r.body?.data(using: .utf8) ?? Data() }
            }
        }
        guard let finalURL = URL(string: curU) else { return }
        if let rule = await engine.findMapRule(for: curM, url: finalURL) {
            applyMapRule(rule, flowID: flowID, method: curM, url: curU, headers: curH, body: curB)
            return
        }
        let flow = MitmFlow(id: flowID, request: MitmFlow.Request(method: curM, url: curU, headers: curH, body: String(data: curB, encoding: .utf8)), event: "request", timestamp: Date().timeIntervalSince1970)
        await engine.notifyFlowUpdate(flow)
        try? await engine.applyTrafficProfile(direction: .uplink, bodySize: curB.count)

        let port = UInt16(finalURL.port ?? (finalURL.scheme == "https" ? 443 : 80))
        let outbound = NWConnection(to: .hostPort(host: .init(finalURL.host!), port: .init(rawValue: port)!), using: finalURL.scheme == "https" ? .tls : .tcp)
        outbound.stateUpdateHandler = { state in
            if case .ready = state {
                var req = "\(curM) \(finalURL.path)\(finalURL.query.map { "?" + $0 } ?? "") HTTP/1.1\r\n"
                for (k, v) in curH { req += "\(k): \(v)\r\n" }
                req += "\r\n"
                outbound.send(content: req.data(using: .utf8), completion: .contentProcessed({ _ in if !curB.isEmpty { outbound.send(content: curB, completion: .contentProcessed({ _ in })) } }))
            }
        }
        outbound.start(queue: .global())
        outbound.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            if let d = data { Task { await self?.handleOutboundResponse(data: d, flowID: flowID, finalURL: finalURL, flow: flow, outbound: outbound) } }
        }
    }

    private func handleOutboundResponse(data: Data, flowID: String, finalURL: URL, flow: MitmFlow, outbound: NWConnection) async {
        if let range = data.firstRange(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
            let hData = data.subdata(in: data.startIndex..<range.lowerBound), bData = data.subdata(in: range.upperBound..<data.endIndex)
            if let hStr = String(data: hData, encoding: .utf8) {
                let lines = hStr.components(separatedBy: "\r\n")
                let code = Int(lines[0].components(separatedBy: " ")[1]) ?? 200
                var h: [String: String] = [:]
                for l in lines.dropFirst() { let p = l.components(separatedBy: ": "); if p.count == 2 { h[p[0]] = p[1] } }
                var fCode = code, fH = h, fB = bData
                try? await engine.applyTrafficProfile(direction: .downlink, bodySize: bData.count)
                if let bp = await engine.findBreakpointRule(for: finalURL), bp.interceptResponse {
                    if let res = await engine.waitForBreakpoint(flowID: flowID, phase: .response, key: bp.key) {
                        if let r = res.response { fCode = r.status; fH = r.headers; fB = r.body.data(using: .utf8) ?? Data() }
                    }
                }
                await engine.notifyFlowUpdate(MitmFlow(id: flowID, request: flow.request, response: .init(status: fCode, headers: fH, body: .init(data: fB, encoding: .utf8)), event: "response", timestamp: flow.timestamp))
                var resp = "HTTP/1.1 \(fCode) OK\r\n"
                for (k, v) in fH { resp += "\(k): \(v)\r\n" }
                resp += "\r\n"
                nwConnection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in self.nwConnection.send(content: fB, completion: .contentProcessed({ _ in outbound.cancel() })) }))
            }
        }
    }

    private func applyMapRule(_ rule: MapRule, flowID: String, method: String, url: String, headers: [String: String], body: Data) {
        let flow = MitmFlow(id: flowID, request: .init(method: method, url: url, headers: headers, body: .init(data: body, encoding: .utf8)), response: .init(status: rule.status, headers: rule.headers, body: rule.body), event: "response", timestamp: Date().timeIntervalSince1970)
        Task { @MainActor in engine.notifyFlowUpdate(flow) }
        var resp = "HTTP/1.1 \(rule.status) OK\r\n"
        for (k, v) in rule.headers { resp += "\(k): \(v)\r\n" }
        if !rule.headers.keys.contains(where: { $0.lowercased() == "content-type" }) { resp += "Content-Type: application/json\r\n" }
        resp += "X-Map-Local: true\r\n\r\n"
        nwConnection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ [weak self] _ in if let b = rule.body.data(using: .utf8) { self?.nwConnection.send(content: b, completion: .contentProcessed({ _ in })) } }))
    }
}
