import Foundation
import Testing
@testable import FRTMProxy

@Suite("Automation redaction")
struct AutomationRedactionTests {
    @Test("Default policy removes credentials, cookies, query tokens, and body")
    func defaultPolicyIsFailClosed() throws {
        let input = AutomationHTTPMessage(
            url: "https://api.example.com/users?token=secret&page=1",
            headers: [
                "Authorization": "Bearer secret",
                "Cookie": "session=secret",
                "Accept": "application/json"
            ],
            body: "{\"password\":\"secret\"}"
        )

        let result = try AutomationRedactor.redact(input)

        #expect(result.url == "https://api.example.com/users?token=%5BREDACTED%5D&page=1")
        #expect(result.headers["Authorization"] == "[REDACTED]")
        #expect(result.headers["Cookie"] == "[REDACTED]")
        #expect(result.headers["Accept"] == "application/json")
        #expect(result.body == nil)
        #expect(result.bodyWasOmitted)
        #expect(!result.bodyWasTruncated)
    }

    @Test("Named-cookie mode preserves only non-sensitive cookies")
    func namedCookieRedaction() throws {
        let policy = RedactionPolicy(cookieMode: .redactNamed)
        let input = AutomationHTTPMessage(headers: ["Cookie": "theme=dark; session=abc; token=xyz"])

        let result = try AutomationRedactor.redact(input, using: policy)

        #expect(result.headers["Cookie"] == "theme=dark;session=[REDACTED];token=[REDACTED]")
    }

    @Test("Included JSON bodies redact nested fields")
    func jsonBodyRedaction() throws {
        let policy = RedactionPolicy(bodyMode: .includeText)
        let input = AutomationHTTPMessage(
            headers: ["Content-Type": "application/json"],
            body: "{\"user\":{\"password\":\"secret\",\"name\":\"Ada\"},\"token\":\"abc\"}"
        )

        let result = try AutomationRedactor.redact(input, using: policy)

        #expect(result.body?.contains("secret") == false)
        #expect(result.body?.contains("abc") == false)
        #expect(result.body?.contains("Ada") == true)
        #expect(result.body?.contains("[REDACTED]") == true)
    }

    @Test("Included bodies respect their UTF-8 byte cap")
    func bodySizeCap() throws {
        let policy = RedactionPolicy(bodyMode: .includeText, maximumBodyBytes: 5)
        let result = try AutomationRedactor.redact(
            AutomationHTTPMessage(body: "abcdefghij"),
            using: policy
        )

        #expect(result.body == "abcde")
        #expect(result.bodyWasTruncated)
        #expect(!result.bodyWasOmitted)
    }

    @Test("Body caps never split a UTF-8 scalar or exceed the byte limit")
    func unicodeBodySizeCap() throws {
        let policy = RedactionPolicy(bodyMode: .includeText, maximumBodyBytes: 5)
        let result = try AutomationRedactor.redact(
            AutomationHTTPMessage(body: "abc💚def"),
            using: policy
        )

        #expect(result.body == "abc")
        #expect((result.body?.utf8.count ?? 0) <= 5)
        #expect(result.bodyWasTruncated)
    }

    @Test("Malformed declared JSON is omitted instead of leaking raw content")
    func malformedJSONIsFailClosed() throws {
        let policy = RedactionPolicy(bodyMode: .includeText)
        let result = try AutomationRedactor.redact(
            AutomationHTTPMessage(
                headers: ["Content-Type": "application/json"],
                body: "{\"password\":\"secret\""
            ),
            using: policy
        )

        #expect(result.body == nil)
        #expect(result.bodyWasOmitted)
    }

    @Test("Decoded policies normalize sensitive names")
    func decodedPolicyNormalization() throws {
        let encoded = try JSONEncoder().encode(RedactionPolicy())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["sensitiveHeaderNames"] = [" AUTHORIZATION "]
        let modified = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RedactionPolicy.self, from: modified)

        #expect(decoded.matchesSensitiveHeader("Authorization"))
    }
}
