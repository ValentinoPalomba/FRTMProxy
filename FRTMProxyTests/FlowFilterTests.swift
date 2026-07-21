import Testing
import Foundation
@testable import FRTMProxy

/// `FlowFilter` (e il suo parser DSL interno `FlowQuery`) è il motore di ricerca
/// della lista flow. Si testa attraverso la superficie pubblica `apply(to:)`.
@Suite("FlowFilter")
struct FlowFilterTests {

    // Fixture di flow eterogenei costruiti da JSON (come arrivano dal bridge).
    private let flows: [MitmFlow] = [
        FlowFixture.make(#"""
        {"id":"1","event":"response",
         "request":{"method":"GET","url":"https://api.example.com/users","headers":{},"body":null},
         "response":{"status":200,"headers":{"content-type":"application/json"},"body":"{\"ok\":true}"},
         "client":{"ip":"127.0.0.1","port":51000},
         "clientApp":{"id":"com.acme.app","displayName":"Acme","bundleIdentifier":"com.acme.app"}}
        """#),
        FlowFixture.make(#"""
        {"id":"2","event":"response",
         "request":{"method":"POST","url":"https://api.example.com/login","headers":{},"body":"secret"},
         "response":{"status":401,"headers":{"content-type":"text/html"},"body":"<html>no</html>"},
         "client":{"ip":"192.168.1.5","port":51001},
         "clientApp":{"id":"com.other.tool","displayName":"Other","bundleIdentifier":"com.other.tool"}}
        """#),
        FlowFixture.make(#"""
        {"id":"3","event":"response",
         "request":{"method":"GET","url":"https://cdn.other.net/image.png","headers":{},"body":null},
         "response":{"status":500,"headers":{"content-type":"image/png","X-Map-Local":"1"},"body":""},
         "client":{"ip":"127.0.0.1","port":51002}}
        """#),
        FlowFixture.make(#"""
        {"id":"4","event":"response",
         "request":{"method":"POST","url":"https://api.example.com/graphql","headers":{"content-type":"application/json"},"body":"{\"operationName\":\"LoadProfile\",\"query\":\"query LoadProfile { profile { id } }\"}"},
         "response":{"status":200,"headers":{"content-type":"application/json"},"body":"{\"data\":{}}"},
         "client":{"ip":"127.0.0.1","port":51003}}
        """#),
    ]

    private func filtered(_ text: String) -> [String] {
        var f = FlowFilter()
        f.searchText = text
        return f.apply(to: flows).map(\.id)
    }

    @Test("Testo vuoto → tutti i flow")
    func emptyReturnsAll() {
        #expect(filtered("") == ["1", "2", "3", "4"])
        #expect(filtered("   ") == ["1", "2", "3", "4"])
    }

    @Test("host: filtra per dominio")
    func hostKey() {
        #expect(filtered("host:api.example.com") == ["1", "2", "4"])
        #expect(filtered("domain:cdn.other.net") == ["3"])
    }

    @Test("method: filtra per metodo (case-insensitive)")
    func methodKey() {
        #expect(filtered("method:post") == ["2", "4"])
        #expect(filtered("method:GET") == ["1", "3"])
    }

    @Test("status: supporta valore esatto, classe Nxx, range e operatori")
    func statusPredicates() {
        #expect(filtered("status:200") == ["1", "4"])
        #expect(filtered("status:2xx") == ["1", "4"])
        #expect(filtered("status:4xx") == ["2"])
        #expect(filtered("status:>=400") == ["2", "3"])
        #expect(filtered("status:400-499") == ["2"])
        #expect(filtered("code:500") == ["3"])
    }

    @Test("Esclusione con -term")
    func exclusion() {
        // Tutti tranne quelli che contengono 'login' da qualche parte
        #expect(filtered("-login") == ["1", "3", "4"])
    }

    @Test("Termini tra virgolette trattati come frase unica")
    func quotedPhrase() {
        // Con le virgolette '<html>no</html>' è un singolo token keyword
        #expect(filtered("\"<html>no</html>\"") == ["2"])
    }

    @Test("type:json usa header e sniffing del body")
    func contentTypeJSON() {
        #expect(filtered("type:json") == ["1", "4"])
    }

    @Test("app:/bundle: filtra per applicazione client")
    func appKey() {
        #expect(filtered("app:acme") == ["1"])
        #expect(filtered("bundle:com.other.tool") == ["2"])
    }

    @Test("ip:/client: filtra per IP del client")
    func clientIPKey() {
        #expect(filtered("ip:127.0.0.1") == ["1", "3", "4"])
        #expect(filtered("client:192.168.1.5") == ["2"])
    }

    @Test("Chiavi combinate sono in AND")
    func combinedKeysAnd() {
        #expect(filtered("host:api.example.com method:get") == ["1"])
    }

    @Test("protocol: e operation: riconoscono GraphQL")
    func protocolInspectionKeys() {
        #expect(filtered("protocol:graphql") == ["4"])
        #expect(filtered("operation:LoadProfile") == ["4"])
        #expect(filtered("-protocol:graphql") == ["1", "2", "3"])
    }

    // MARK: - Flag booleani

    @Test("showErrorsOnly tiene solo status >= 400")
    func showErrorsOnly() {
        var f = FlowFilter()
        f.showErrorsOnly = true
        #expect(f.apply(to: flows).map(\.id) == ["2", "3"])
    }

    @Test("showMappedOnly tiene solo i flow con header X-Map-Local")
    func showMappedOnly() {
        var f = FlowFilter()
        f.showMappedOnly = true
        #expect(f.apply(to: flows).map(\.id) == ["3"])
    }
}
