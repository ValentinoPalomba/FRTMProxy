import Foundation

struct RedactionPolicy: Codable, Equatable, Sendable {
    enum BodyMode: String, Codable, Sendable {
        case omit
        case includeText
    }

    enum CookieMode: String, Codable, Sendable {
        case redactAll
        case redactNamed
    }

    static let defaults = RedactionPolicy()

    var sensitiveHeaderNames: Set<String>
    var sensitiveQueryParameterNames: Set<String>
    var sensitiveBodyFieldNames: Set<String>
    var sensitiveCookieNames: Set<String>
    var cookieMode: CookieMode
    var bodyMode: BodyMode
    var maximumBodyBytes: Int
    var replacement: String

    private enum CodingKeys: String, CodingKey {
        case sensitiveHeaderNames
        case sensitiveQueryParameterNames
        case sensitiveBodyFieldNames
        case sensitiveCookieNames
        case cookieMode
        case bodyMode
        case maximumBodyBytes
        case replacement
    }

    init(
        sensitiveHeaderNames: Set<String> = [
            "authorization", "proxy-authorization", "cookie", "set-cookie",
            "x-api-key", "x-auth-token", "x-access-token"
        ],
        sensitiveQueryParameterNames: Set<String> = [
            "access_token", "api_key", "apikey", "auth", "authorization",
            "client_secret", "password", "refresh_token", "secret", "token"
        ],
        sensitiveBodyFieldNames: Set<String> = [
            "access_token", "api_key", "apikey", "authorization", "client_secret",
            "password", "refresh_token", "secret", "token"
        ],
        sensitiveCookieNames: Set<String> = [
            "auth", "authorization", "jwt", "session", "sessionid", "token"
        ],
        cookieMode: CookieMode = .redactAll,
        bodyMode: BodyMode = .omit,
        maximumBodyBytes: Int = AutomationLimits.defaults.maximumBodyBytes,
        replacement: String = "[REDACTED]"
    ) {
        self.sensitiveHeaderNames = Self.normalized(sensitiveHeaderNames)
        self.sensitiveQueryParameterNames = Self.normalized(sensitiveQueryParameterNames)
        self.sensitiveBodyFieldNames = Self.normalized(sensitiveBodyFieldNames)
        self.sensitiveCookieNames = Self.normalized(sensitiveCookieNames)
        self.cookieMode = cookieMode
        self.bodyMode = bodyMode
        self.maximumBodyBytes = maximumBodyBytes
        self.replacement = replacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sensitiveHeaderNames: try container.decode(Set<String>.self, forKey: .sensitiveHeaderNames),
            sensitiveQueryParameterNames: try container.decode(Set<String>.self, forKey: .sensitiveQueryParameterNames),
            sensitiveBodyFieldNames: try container.decode(Set<String>.self, forKey: .sensitiveBodyFieldNames),
            sensitiveCookieNames: try container.decode(Set<String>.self, forKey: .sensitiveCookieNames),
            cookieMode: try container.decode(CookieMode.self, forKey: .cookieMode),
            bodyMode: try container.decode(BodyMode.self, forKey: .bodyMode),
            maximumBodyBytes: try container.decode(Int.self, forKey: .maximumBodyBytes),
            replacement: try container.decode(String.self, forKey: .replacement)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensitiveHeaderNames, forKey: .sensitiveHeaderNames)
        try container.encode(sensitiveQueryParameterNames, forKey: .sensitiveQueryParameterNames)
        try container.encode(sensitiveBodyFieldNames, forKey: .sensitiveBodyFieldNames)
        try container.encode(sensitiveCookieNames, forKey: .sensitiveCookieNames)
        try container.encode(cookieMode, forKey: .cookieMode)
        try container.encode(bodyMode, forKey: .bodyMode)
        try container.encode(maximumBodyBytes, forKey: .maximumBodyBytes)
        try container.encode(replacement, forKey: .replacement)
    }

    func validate(limits: AutomationLimits = .defaults) throws {
        guard maximumBodyBytes > 0, maximumBodyBytes <= limits.maximumBodyBytes else {
            throw RedactionPolicyError.invalidMaximumBodyBytes(allowed: limits.maximumBodyBytes)
        }
        guard !replacement.isEmpty else { throw RedactionPolicyError.emptyReplacement }
    }

    func matchesSensitiveHeader(_ name: String) -> Bool {
        sensitiveHeaderNames.contains(Self.normalize(name))
    }

    func matchesSensitiveQueryParameter(_ name: String) -> Bool {
        sensitiveQueryParameterNames.contains(Self.normalize(name))
    }

    func matchesSensitiveBodyField(_ name: String) -> Bool {
        sensitiveBodyFieldNames.contains(Self.normalize(name))
    }

    func matchesSensitiveCookie(_ name: String) -> Bool {
        sensitiveCookieNames.contains(Self.normalize(name))
    }

    private static func normalized(_ values: Set<String>) -> Set<String> {
        Set(values.map(normalize).filter { !$0.isEmpty })
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum RedactionPolicyError: Error, Equatable {
    case invalidMaximumBodyBytes(allowed: Int)
    case emptyReplacement
}
