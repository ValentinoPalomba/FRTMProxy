import Foundation

/// Runtime messages use the app's selected language, just like SwiftUI's locale.
enum AppLocalization {
    static var bundle: Bundle {
        let language = AppLanguage.language(
            with: CaptureStorageConfiguration.preferences.string(forKey: "settings.language")
        )
        return bundle(for: language)
    }

    static func bundle(for language: AppLanguage) -> Bundle {
        guard let directory = Bundle.main.url(forResource: language.id, withExtension: "lproj"),
              let localized = Bundle(url: directory) else { return .main }
        return localized
    }
}
