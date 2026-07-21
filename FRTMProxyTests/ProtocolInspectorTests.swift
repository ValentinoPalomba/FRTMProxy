import Foundation
import Testing
@testable import FRTMProxy

@Suite("ProtocolInspector")
struct ProtocolInspectorTests {
    @Test("GraphQL espone operationName e variables")
    func graphQL() {
        let result = ProtocolInspector.inspect(
            body: #"{"operationName":"Users","query":"query Users { users { id } }","variables":{"limit":2}}"#,
            headers: ["Content-Type": "application/json"]
        )
        #expect(result?.kind == .graphQL)
        #expect(result?.summary == "Users")
        #expect(result?.sections.contains(where: { $0.id == "variables" }) == true)
    }

    @Test("JWT viene decodificato senza dichiarare la firma verificata")
    func jwt() {
        let result = ProtocolInspector.inspect(
            body: nil,
            headers: ["Authorization": "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMifQ."]
        )
        #expect(result?.kind == .jwt)
        #expect(result?.summary == "Signature is not verified")
        #expect(result?.sections.count == 3)
    }

    @Test("SSE mantiene gli eventi separati")
    func sse() {
        let result = ProtocolInspector.inspect(
            body: "event: ping\ndata: one\n\nevent: ping\ndata: two\n",
            headers: ["content-type": "text/event-stream"]
        )
        #expect(result?.kind == .serverSentEvents)
        #expect(result?.sections.count == 2)
    }

    @Test("gRPC decodifica più frame protobuf")
    func grpc() {
        let frame = Data([0, 0, 0, 0, 3, 0x08, 0x96, 0x01]).base64EncodedString()
        let result = ProtocolInspector.inspect(body: frame, headers: ["content-type": "application/grpc"])
        #expect(result?.kind == .grpc)
        #expect(result?.sections.first?.content.contains("1: varint 150") == true)
    }

    @Test("Protobuf malformato non legge oltre il buffer")
    func malformedProtobuf() {
        #expect(ProtobufWireDecoder.decode(Data([0x0A, 0x08, 0x01])) == nil)
    }
}
