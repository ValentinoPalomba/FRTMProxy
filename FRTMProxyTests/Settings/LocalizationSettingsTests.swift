import Foundation
import Testing
@testable import FRTMProxy

@MainActor
@Suite("Localization settings")
struct LocalizationSettingsTests {
    @Test("Missing language defaults to English")
    func missingLanguageDefaultsToEnglish() {
        let defaults = temporaryDefaults()
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.selectedLanguage == .english)
        #expect(settings.selectedLanguageID == "en")
    }

    @Test("Invalid language defaults to English")
    func invalidLanguageDefaultsToEnglish() {
        let defaults = temporaryDefaults()
        defaults.set("xx-invalid", forKey: "settings.language")

        let settings = SettingsStore(defaults: defaults)

        #expect(settings.selectedLanguage == .english)
        #expect(settings.selectedLanguageID == "en")
    }

    @Test("Language selection round-trips")
    func languageSelectionRoundTrips() {
        let defaults = temporaryDefaults()
        let settings = SettingsStore(defaults: defaults)

        settings.selectedLanguageID = AppLanguage.japanese.id

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.selectedLanguage == .japanese)
        #expect(restored.selectedLanguageID == "ja")
    }

    @Test("Supported IDs match the project locales")
    func supportedIDsMatchProjectLocales() throws {
        let expected = Set(["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans"])
        #expect(Set(AppLanguage.allCases.map(\.id)) == expected)

        let catalog = try loadJSONObject(named: "Localizable", extension: "xcstrings")
        #expect(catalog["sourceLanguage"] as? String == "en")

        let project = try String(contentsOf: projectRoot.appending(path: "project.yml"), encoding: .utf8)
        let knownRegionsLine = try #require(
            project.split(separator: "\n").first(where: { $0.contains("knownRegions:") })
        )
        let configuredRegions = Set(
            knownRegionsLine
                .split(separator: "[", maxSplits: 1)
                .last?
                .split(separator: "]", maxSplits: 1)
                .first?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        )
        #expect(configuredRegions.subtracting(["Base"]) == expected)
    }

    @Test("Catalog translations are complete and preserve placeholders")
    func catalogTranslationsAreComplete() throws {
        let catalog = try loadJSONObject(named: "Localizable", extension: "xcstrings")
        let strings = try #require(catalog["strings"] as? [String: Any])
        let targets = ["de", "es", "fr", "it", "ja", "pt-BR", "zh-Hans"]

        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  entry["shouldTranslate"] as? Bool != false else {
                continue
            }
            let localizations = try #require(entry["localizations"] as? [String: Any], "Missing localizations for \(key)")
            let sourceSignature = placeholderSignature(key)

            for target in targets {
                let localization = try #require(localizations[target] as? [String: Any], "Missing \(target) for \(key)")
                let unit = try #require(localization["stringUnit"] as? [String: Any], "Missing string unit for \(target): \(key)")
                #expect(unit["state"] as? String == "translated")
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty)
                #expect(placeholderSignature(value) == sourceSignature)
            }
        }
    }

    @Test("Info.plist permission text covers every locale")
    func infoPlistTranslationsAreComplete() throws {
        let catalog = try loadJSONObject(named: "InfoPlist", extension: "xcstrings")
        let strings = try #require(catalog["strings"] as? [String: Any])
        let entry = try #require(strings["NSLocationWhenInUseUsageDescription"] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])

        for locale in AppLanguage.allCases {
            let localization = try #require(localizations[locale.id] as? [String: Any])
            let unit = try #require(localization["stringUnit"] as? [String: Any])
            #expect(unit["state"] as? String == "translated")
            #expect(!(unit["value"] as? String ?? "").isEmpty)
        }
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "LocalizationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func loadJSONObject(named name: String, extension fileExtension: String) throws -> [String: Any] {
        let url = projectRoot
            .appending(path: "FRTMProxy")
            .appending(path: "\(name).\(fileExtension)")
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func placeholderSignature(_ value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:[-+0 #']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|q|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
}
