import Testing
import Foundation
@testable import FRTMProxy

/// Verifica che `MapRuleKeyBuilder` (Swift) generi le stesse chiavi Map Local di
/// `bridge.py` (Python). I due lati DEVONO restare allineati: una chiave prodotta
/// dall'app che non combacia con quella calcolata dal bridge fa sì che un mock non
/// venga applicato al traffico corrispondente.
///
/// I valori `expectedKey` sono golden generati replicando esattamente la logica di
/// `FRTMProxy/bridge.py` (map_local_key / canonical_request_signature / canonical_query
/// / canonical_body) con questo script Python — rigenerabile in caso di modifica volontaria:
///
/// ```python
/// import hashlib, json
/// from urllib.parse import urlsplit, parse_qsl
/// def canonical_query(url):
///     items = parse_qsl(urlsplit(url or "").query or "", keep_blank_values=True)
///     if not items: return ""
///     items.sort(key=lambda kv:(kv[0],kv[1]))
///     return "&".join(f"{k}={v}" for k,v in items)
/// def canonical_body(body, ct):
///     if not body: return ""
///     ct=(ct or "").lower()
///     if "application/json" in ct: return json.dumps(json.loads(body), sort_keys=True, separators=(",",":"))
///     if "application/x-www-form-urlencoded" in ct:
///         items=parse_qsl(body, keep_blank_values=True); items.sort(key=lambda kv:(kv[0],kv[1]))
///         return "&".join(f"{k}={v}" for k,v in items) if items else ""
///     return body
/// def key(host, path, method, url, body, ct):
///     sig=(method or "GET").strip().upper()+"\n"+canonical_query(url)+"\n"+canonical_body((body or "").replace("\r\n","\n").replace("\r","\n"),ct)
///     return host+(path or "/")+"#"+hashlib.sha256(sig.encode()).hexdigest()[:12]
/// ```
@Suite("MapRuleKeyBuilder ↔ bridge.py")
struct MapRuleKeyBuilderTests {

    struct GoldenCase: Sendable, CustomStringConvertible {
        let name: String
        let host: String
        let path: String
        let method: String
        let url: String
        let body: String?
        let contentType: String?
        let expectedKey: String

        var description: String { name }
        var headers: [String: String] { contentType.map { ["Content-Type": $0] } ?? [:] }
    }

    static let golden: [GoldenCase] = [
        GoldenCase(name: "simple_get", host: "api.example.com", path: "/users", method: "GET",
                   url: "https://api.example.com/users", body: nil, contentType: nil,
                   expectedKey: "api.example.com/users#69a1c0c62ded"),
        GoldenCase(name: "query_sorted", host: "api.example.com", path: "/search", method: "GET",
                   url: "https://api.example.com/search?b=2&a=1", body: nil, contentType: nil,
                   expectedKey: "api.example.com/search#adaf5b6aa4aa"),
        GoldenCase(name: "json_body_sorted_keys", host: "api.example.com", path: "/users", method: "POST",
                   url: "https://api.example.com/users", body: #"{"b":2,"a":1}"#, contentType: "application/json",
                   expectedKey: "api.example.com/users#bdf5e6f49ea6"),
        GoldenCase(name: "form_urlencoded_sorted", host: "api.example.com", path: "/login", method: "POST",
                   url: "https://api.example.com/login", body: "b=2&a=1", contentType: "application/x-www-form-urlencoded",
                   expectedKey: "api.example.com/login#9ae2082aea22"),
        // Caso critico: '+' percent-encoded (%2B) deve restare '+', NON diventare spazio.
        GoldenCase(name: "query_plus_encoded", host: "api.example.com", path: "/s", method: "GET",
                   url: "https://api.example.com/s?name=a%2Bb", body: nil, contentType: nil,
                   expectedKey: "api.example.com/s#2878c8c43cf9"),
        // Caso complementare: '+' letterale deve diventare spazio.
        GoldenCase(name: "query_plus_literal", host: "api.example.com", path: "/s", method: "GET",
                   url: "https://api.example.com/s?name=a+b", body: nil, contentType: nil,
                   expectedKey: "api.example.com/s#96a549f3f817"),
        GoldenCase(name: "empty_path_normalized", host: "api.example.com", path: "", method: "GET",
                   url: "https://api.example.com", body: nil, contentType: nil,
                   expectedKey: "api.example.com/#69a1c0c62ded"),
        GoldenCase(name: "blank_query_value", host: "api.example.com", path: "/q", method: "GET",
                   url: "https://api.example.com/q?x=&y=1", body: nil, contentType: nil,
                   expectedKey: "api.example.com/q#8eb740550203"),
    ]

    @Test("Chiave allineata a bridge.py", arguments: golden)
    func matchesPythonBridge(_ c: GoldenCase) {
        let key = MapRuleKeyBuilder.makeKey(
            host: c.host, path: c.path, method: c.method,
            url: c.url, headers: c.headers, body: c.body
        )
        #expect(key == c.expectedKey, "caso \(c.name): atteso \(c.expectedKey), ottenuto \(key)")
    }

    // MARK: - Proprietà strutturali

    @Test("makeKey è deterministico e ha formato base#12hex")
    func makeKeyFormat() {
        let key = MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "GET",
                                            url: "https://h.com/p", headers: [:], body: nil)
        #expect(key == MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "GET",
                                                 url: "https://h.com/p", headers: [:], body: nil))
        let parts = key.split(separator: "#")
        #expect(parts.count == 2)
        #expect(parts[0] == "h.com/p")
        #expect(parts[1].count == 12)
        #expect(parts[1].allSatisfy { $0.isHexDigit })
    }

    @Test("method viene normalizzato (case/whitespace) e default GET")
    func methodNormalization() {
        let base = MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "GET", url: "https://h.com/p", headers: [:], body: nil)
        #expect(MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "  get ", url: "https://h.com/p", headers: [:], body: nil) == base)
        #expect(MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "", url: "https://h.com/p", headers: [:], body: nil) == base)
        #expect(MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: nil, url: "https://h.com/p", headers: [:], body: nil) == base)
    }

    @Test("JSON semanticamente uguale → stessa chiave a prescindere dall'ordine chiavi")
    func jsonOrderIndependence() {
        let ct = ["content-type": "application/json"]
        let k1 = MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "POST", url: "https://h.com/p", headers: ct, body: #"{"a":1,"b":2}"#)
        let k2 = MapRuleKeyBuilder.makeKey(host: "h.com", path: "/p", method: "POST", url: "https://h.com/p", headers: ct, body: #"{"b":2,"a":1}"#)
        #expect(k1 == k2)
    }

    // MARK: - disambiguatedKey / baseKey / variantTag

    @Test("disambiguatedKey aggiunge ~N solo in caso di collisione")
    func disambiguation() {
        #expect(MapRuleKeyBuilder.disambiguatedKey(preferredKey: "k#abc", existingKeys: []) == "k#abc")
        #expect(MapRuleKeyBuilder.disambiguatedKey(preferredKey: "k#abc", existingKeys: ["k#abc"]) == "k#abc~2")
        #expect(MapRuleKeyBuilder.disambiguatedKey(preferredKey: "k#abc", existingKeys: ["k#abc", "k#abc~2"]) == "k#abc~3")
    }

    @Test("baseKey(from:) e variantTag(from:) separano base e signature")
    func baseAndVariant() {
        #expect(MapRuleKeyBuilder.baseKey(from: "host.com/path#deadbeef") == "host.com/path")
        #expect(MapRuleKeyBuilder.variantTag(from: "host.com/path#deadbeef") == "deadbeef")
        #expect(MapRuleKeyBuilder.baseKey(from: "host.com/path") == "host.com/path")
        #expect(MapRuleKeyBuilder.variantTag(from: "host.com/path") == nil)
    }

    @Test("baseKey normalizza il path vuoto a /")
    func baseKeyEmptyPath() {
        #expect(MapRuleKeyBuilder.baseKey(host: "h.com", path: "") == "h.com/")
        #expect(MapRuleKeyBuilder.baseKey(host: "h.com", path: "/x") == "h.com/x")
    }
}
