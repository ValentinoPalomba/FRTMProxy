import Combine
import Foundation

protocol ProxyServiceProtocol: AnyObject {
    var isRunningPublisher: AnyPublisher<Bool, Never> { get }
    var onLog: ((String) -> Void)? { get set }

    func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) throws
    func stopProxy()
    func clearFlows()
    func mockResponse(for flowID: String, body: String)
    func mockRule(_ rule: MapRule)
    func deleteRule(forKey key: String)
    func mockRequest(for flowID: String, body: String, headers: [String: String]?)
    func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?)
    func applyTrafficProfile(_ profile: TrafficProfile)
    func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String])
    func updateBreakpointRule(_ rule: FlowBreakpointRule)
    func deleteBreakpointRule(forKey key: String)
    func resumeBreakpoint(flowID: String, phase: FlowBreakpointPhase, requestPayload: BreakpointRequestPayload?, responsePayload: BreakpointResponsePayload?)
}
