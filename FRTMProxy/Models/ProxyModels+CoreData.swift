import CoreData
import Foundation

@objc(MitmFlowEntity)
public class MitmFlowEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var event: String
    @NSManaged public var timestamp: TimeInterval
    @NSManaged public var clientIP: String?
    @NSManaged public var clientPort: Int32
    @NSManaged public var requestData: Data?
    @NSManaged public var responseData: Data?
    @NSManaged public var breakpointData: Data?

    private static var jsonEncoder = JSONEncoder()
    private static var jsonDecoder = JSONDecoder()

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MitmFlowEntity> {
        return NSFetchRequest<MitmFlowEntity>(entityName: "MitmFlowEntity")
    }

    func update(from flow: MitmFlow) {
        self.id = flow.id
        self.event = flow.event
        self.timestamp = flow.timestamp ?? Date().timeIntervalSince1970
        self.clientIP = flow.client?.ip
        self.clientPort = Int32(flow.client?.port ?? 0)

        if let request = flow.request {
            self.requestData = try? Self.jsonEncoder.encode(request)
        }
        if let response = flow.response {
            self.responseData = try? Self.jsonEncoder.encode(response)
        }
        if let breakpoint = flow.breakpoint {
            self.breakpointData = try? Self.jsonEncoder.encode(breakpoint)
        } else {
            self.breakpointData = nil
        }
    }

    func toMitmFlow() -> MitmFlow {
        var request: MitmFlow.Request?
        if let data = requestData {
            request = try? Self.jsonDecoder.decode(MitmFlow.Request.self, from: data)
        }

        var response: MitmFlow.Response?
        if let data = responseData {
            response = try? Self.jsonDecoder.decode(MitmFlow.Response.self, from: data)
        }

        var breakpoint: FlowBreakpointMetadata?
        if let data = breakpointData {
            breakpoint = try? Self.jsonDecoder.decode(FlowBreakpointMetadata.self, from: data)
        }

        let client = MitmFlow.Client(ip: clientIP ?? "", port: Int(clientPort))

        return MitmFlow(
            id: id,
            request: request,
            response: response,
            event: event,
            timestamp: timestamp,
            client: client,
            breakpoint: breakpoint
        )
    }
}
