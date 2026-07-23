import Testing
import Foundation
@testable import FRTMProxy

@Suite("FormattingUtils")
struct FormattingUtilsTests {

    // MARK: parseHeaders

    @Test("parseHeaders estrae coppie chiave/valore separando sul primo ':'")
    func parseHeadersBasic() {
        let headers = FormattingUtils.parseHeaders("Content-Type: application/json\nAuthorization: Bearer abc")
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["Authorization"] == "Bearer abc")
    }

    @Test("parseHeaders preserva ':' nel valore (maxSplits=1)")
    func parseHeadersColonInValue() {
        let headers = FormattingUtils.parseHeaders("X-Time: 10:20:30")
        #expect(headers["X-Time"] == "10:20:30")
    }

    @Test("parseHeaders ignora righe malformate")
    func parseHeadersMalformed() {
        let headers = FormattingUtils.parseHeaders("valida: si\nrigasenzavalore\n: senza-nome")
        #expect(headers.count == 1)
        #expect(headers["valida"] == "si")
    }

    // MARK: formattedHeaders

    @Test("formattedHeaders ordina case-insensitive per chiave")
    func formattedHeadersSorted() {
        let text = FormattingUtils.formattedHeaders(["Zeta": "1", "alpha": "2", "Beta": "3"])
        #expect(text == "alpha: 2\nBeta: 3\nZeta: 1")
    }

    // MARK: splitHostAndPath

    @Test("splitHostAndPath con scheme esplicito")
    func splitWithScheme() {
        let split = FormattingUtils.splitHostAndPath(from: "https://api.example.com/v1/users?q=1#frag")
        #expect(split?.host == "api.example.com")
        #expect(split?.path == "/v1/users?q=1#frag")
    }

    @Test("splitHostAndPath aggiunge lo scheme di default quando assente")
    func splitWithoutScheme() {
        let split = FormattingUtils.splitHostAndPath(from: "api.example.com/path")
        #expect(split?.host == "api.example.com")
        #expect(split?.path == "/path")
    }

    @Test("splitHostAndPath usa '/' quando il path è vuoto")
    func splitEmptyPath() {
        let split = FormattingUtils.splitHostAndPath(from: "https://api.example.com")
        #expect(split?.host == "api.example.com")
        #expect(split?.path == "/")
    }

    @Test("splitHostAndPath restituisce nil per stringhe non-URL")
    func splitNonURL() {
        #expect(FormattingUtils.splitHostAndPath(from: "solo testo") == nil)
        #expect(FormattingUtils.splitHostAndPath(from: "") == nil)
    }

    // MARK: formattedBodyForEdit

    @Test("formattedBodyForEdit fa pretty-print del JSON")
    func prettyJSON() {
        let pretty = FormattingUtils.formattedBodyForEdit(#"{"a":1}"#)
        #expect(pretty.contains("\n"))
        #expect(pretty.contains("\"a\""))
    }

    @Test("formattedBodyForEdit lascia invariato il non-JSON")
    func nonJSONUnchanged() {
        #expect(FormattingUtils.formattedBodyForEdit("plain text") == "plain text")
        #expect(FormattingUtils.formattedBodyForEdit(nil) == "")
    }
}
