import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case italian = "it"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case brazilianPortuguese = "pt-BR"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var autonym: String {
        switch self {
        case .english: "English"
        case .italian: "Italiano"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .brazilianPortuguese: "Português (Brasil)"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func language(with id: String?) -> AppLanguage {
        id.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}
