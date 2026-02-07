import Combine
import Foundation

protocol ProxyServiceProtocol: AnyObject {
    @MainActor var flowsPublisher: AnyPublisher<[String: MitmFlow], Never> { get }
    @MainActor var isRunningPublisher: AnyPublisher<Bool, Never> { get }
    var onLog: ((String) -> Void)? { get set }

    @MainActor func startProxy(port: Int?, restrictToHosts: Bool, hosts: [String]) async throws
    @MainActor func stopProxy()
    @MainActor func clearFlows()
    @MainActor func mockResponse(for flowID: String, body: String)
    @MainActor func mockRule(_ rule: MapRule)
    @MainActor func deleteRule(forKey key: String)
    @MainActor func mockRequest(for flowID: String, body: String, headers: [String: String]?)
    @MainActor func mockResponse(for flowID: String, body: String, status: Int?, headers: [String: String]?)
    @MainActor func applyTrafficProfile(_ profile: TrafficProfile)
    @MainActor func retryFlow(flowID: String, method: String, url: String, body: String?, headers: [String: String])
    @MainActor func updateBreakpointRule(_ rule: FlowBreakpointRule)
    @MainActor func deleteBreakpointRule(forKey key: String)
    @MainActor func resumeBreakpoint(flowID: String, phase: FlowBreakpointPhase, requestPayload: BreakpointRequestPayload?, responsePayload: BreakpointResponsePayload?)
}
