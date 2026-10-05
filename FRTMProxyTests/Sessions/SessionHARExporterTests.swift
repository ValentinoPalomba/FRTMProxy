import Foundation
import Testing
@testable import FRTMProxy

@Suite("Captured HAR export")
struct SessionHARExporterTests {
    @Test func recordedTimingProtocolDuplicatesAndDefaultRedaction() throws {
        let bytes = Data(#"{"id":"flow","event":"response","requestTimestamp":100,"responseTimestamp":100.25,"request":{"method":"GET","url":"https://user:secret@example.com/data?token=secret","headers":{"Authorization":"Bearer secret"},"body":null,"httpVersion":"HTTP/2"},"response":{"status":200,"headers":{"Set-Cookie":"session=secret"},"headerFields":[{"name":"Set-Cookie","value":"first=1"},{"name":"Set-Cookie","value":"second=2"}],"body":"body-secret","httpVersion":"HTTP/2","byteCount":11}}"#.utf8)
        let flow = try JSONDecoder().decode(MitmFlow.self, from: bytes)
        let exported = try SessionHARExporter.data(flows: [flow])
        let text = String(decoding: exported, as: UTF8.self)
        #expect(!text.contains("secret"))
        let file = try HARCollectionConverter.harDecoder.decode(HARFile.self, from: exported)
        #expect(file.log.entries.first?.time == 250)
        #expect(file.log.entries.first?.response.httpVersion == "HTTP/2")
        #expect(file.log.entries.first?.response.headers?.count == 2)
        #expect(file.log.entries.first?.response.content?.text == nil)

        let full = try SessionHARExporter.data(flows: [flow], redacted: false)
        let imported = try HARCollectionConverter.importCollection(from: full, name: "Capture")
        #expect(imported.rules.first?.body == "body-secret")
    }
}
