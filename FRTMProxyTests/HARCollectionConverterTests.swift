import Testing
import Foundation
@testable import FRTMProxy

@Suite("HARCollectionConverter")
struct HARCollectionConverterTests {

    // MARK: Round-trip

    @Test("Round-trip MapCollection → HAR → MapCollection preserva i campi semantici")
    func roundTrip() throws {
        let rule = MapRule(
            key: "api.example.com/users#deadbeef00",
            host: "api.example.com",
            path: "/users",
            scheme: "https",
            request: MapRuleRequest(method: "POST", url: "https://api.example.com/users", headers: [:], body: "{\"n\":1}"),
            body: "{\"created\":true}",
            status: 201,
            headers: ["Content-Type": "application/json"]
        )
        let collection = MapCollection(name: "Src", rules: [rule])

        let har = HARCollectionConverter.exportHAR(collection: collection)
        let data = try HARCollectionConverter.harEncoder(prettyPrinted: false).encode(har)
        let imported = try HARCollectionConverter.importCollection(from: data, name: "Dst")

        #expect(imported.name == "Dst")
        #expect(imported.rules.count == 1)
        let r = try #require(imported.rules.first)
        #expect(r.host == "api.example.com")
        #expect(r.path == "/users")
        #expect(r.status == 201)
        #expect(r.body == "{\"created\":true}")
        #expect(r.scheme == "https")
        #expect(r.request?.method == "POST")
        #expect(r.headers["Content-Type"] == "application/json")
    }

    // MARK: Import — decodifica body

    @Test("Import: body base64 di testo UTF-8 viene decodificato")
    func importBase64Text() throws {
        let payload = "{\"hello\":\"world\"}"
        let b64 = Data(payload.utf8).base64EncodedString()
        let har = harJSON(status: 200, mimeType: "application/json", text: b64, encoding: "base64")
        let imported = try HARCollectionConverter.importCollection(from: Data(har.utf8), name: "X")
        #expect(imported.rules.first?.body == payload)
    }

    @Test("Import: body base64 binario (non-UTF8) diventa una data URL")
    func importBase64Binary() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0]) // header JPEG, non-UTF8
        let b64 = bytes.base64EncodedString()
        let har = harJSON(status: 200, mimeType: "image/jpeg", text: b64, encoding: "base64")
        let imported = try HARCollectionConverter.importCollection(from: Data(har.utf8), name: "X")
        #expect(imported.rules.first?.body == "data:image/jpeg;base64,\(b64)")
    }

    @Test("Import: text senza encoding resta invariato")
    func importPlainText() throws {
        let har = harJSON(status: 200, mimeType: "text/plain", text: "ciao", encoding: nil)
        let imported = try HARCollectionConverter.importCollection(from: Data(har.utf8), name: "X")
        #expect(imported.rules.first?.body == "ciao")
    }

    @Test("Import: entry con URL non valido viene saltata")
    func importSkipsInvalidURL() throws {
        let har = """
        {"log":{"version":"1.2","entries":[
          {"request":{"method":"GET","url":"not a url","headers":[]},
           "response":{"status":200,"headers":[],"content":{"text":"x"}}}
        ]}}
        """
        let imported = try HARCollectionConverter.importCollection(from: Data(har.utf8), name: "X")
        #expect(imported.rules.isEmpty)
    }

    // MARK: Helpers

    private func harJSON(status: Int, mimeType: String, text: String, encoding: String?) -> String {
        let content: String
        if let encoding {
            content = "{\"mimeType\":\"\(mimeType)\",\"text\":\"\(text)\",\"encoding\":\"\(encoding)\"}"
        } else {
            content = "{\"mimeType\":\"\(mimeType)\",\"text\":\"\(text)\"}"
        }
        return """
        {"log":{"version":"1.2","entries":[
          {"request":{"method":"GET","url":"https://api.example.com/data","headers":[]},
           "response":{"status":\(status),"headers":[{"name":"Content-Type","value":"\(mimeType)"}],"content":\(content)}}
        ]}}
        """
    }
}
