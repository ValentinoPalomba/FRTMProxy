import SwiftUI

struct AppTheme: Identifiable {
    enum Category {
        case automatic
        case light
        case dark
    }

    let id: String
    let name: String
    let description: String
    let preferredColorScheme: ColorScheme?
    let category: Category
    let previewSwatches: [Color]
    private let paletteBuilder: (ColorScheme) -> DesignSystem.ColorPalette

    init(
        id: String,
        name: String,
        description: String,
        preferredColorScheme: ColorScheme?,
        category: Category,
        previewSwatches: [Color],
        palette: @escaping (ColorScheme) -> DesignSystem.ColorPalette
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.preferredColorScheme = preferredColorScheme
        self.category = category
        self.previewSwatches = previewSwatches
        self.paletteBuilder = palette
    }

    func palette(using interfaceStyle: ColorScheme) -> DesignSystem.ColorPalette {
        paletteBuilder(interfaceStyle)
    }
}

enum ThemeLibrary {
    private static let systemTheme = AppTheme(
        id: "system",
        name: "Sistema (Automatico)",
        description: "Segue l'aspetto di macOS e usa la palette originale dell'app.",
        preferredColorScheme: nil,
        category: .automatic,
        previewSwatches: [
            Color(hex: "F9F9FB"),
            Color(hex: "111927"),
            Color(hex: "0A84FF")
        ],
        palette: { scheme in
            DesignSystem.Colors.palette(scheme)
        }
    )

    private static let xcodeLight = AppTheme(
        id: "xcode-light",
        name: "Xcode Light",
        description: "Ispirato al tema chiaro di Xcode, ideale per ambienti luminosi.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "F5F5F7"),
            Color(hex: "FFFFFF"),
            Color(hex: "0A84FF")
        ],
        palette: { _ in
            palette(
                background: "F5F5F7",
                surface: "FFFFFF",
                surfaceElevated: "ECEEF3",
                accent: "0A84FF",
                accentSecondary: "FF9F0A",
                success: "30D158",
                warning: "FF9F0A",
                danger: "FF3B30",
                textPrimary: "131417",
                textSecondary: "5E5E65",
                border: "D2D2D7"
            )
        }
    )

    private static let xcodeDark = AppTheme(
        id: "xcode-dark",
        name: "Xcode Dark",
        description: "Palette high-contrast come il tema scuro di Xcode.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "1C1C1E"),
            Color(hex: "2C2C3A"),
            Color(hex: "0A84FF")
        ],
        palette: { _ in
            palette(
                background: "1C1C1E",
                surface: "1F1F23",
                surfaceElevated: "2C2C3A",
                accent: "0A84FF",
                accentSecondary: "64D2FF",
                success: "30D158",
                warning: "FFD60A",
                danger: "FF453A",
                textPrimary: "F2F2F7",
                textSecondary: "8E8E93",
                border: "32323C"
            )
        }
    )

    private static let vscodeLight = AppTheme(
        id: "vscode-light",
        name: "VS Code Light",
        description: "Colori puliti e neutri ispirati al tema Light+ di VS Code.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "F3F3F3"),
            Color(hex: "FFFFFF"),
            Color(hex: "007ACC")
        ],
        palette: { _ in
            palette(
                background: "F3F3F3",
                surface: "FFFFFF",
                surfaceElevated: "ECECEC",
                accent: "007ACC",
                accentSecondary: "FFCC00",
                success: "16A34A",
                warning: "D97706",
                danger: "DC2626",
                textPrimary: "1E1E1E",
                textSecondary: "5E5E5E",
                border: "D4D4D4"
            )
        }
    )

    private static let vscodeDark = AppTheme(
        id: "vscode-dark",
        name: "VS Code Dark",
        description: "Ricrea il look del classico tema Dark+.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "1E1E1E"),
            Color(hex: "252526"),
            Color(hex: "569CD6")
        ],
        palette: { _ in
            palette(
                background: "1E1E1E",
                surface: "252526",
                surfaceElevated: "2D2D30",
                accent: "569CD6",
                accentSecondary: "C586C0",
                success: "6A9955",
                warning: "D7BA7D",
                danger: "F44747",
                textPrimary: "F3F3F3",
                textSecondary: "A8A8A8",
                border: "3C3C3C"
            )
        }
    )

    private static let prideLight = AppTheme(
        id: "pride-light",
        name: "Pride Light",
        description: "Palette vibrante arcobaleno per interfacce chiare.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "FF2D55"),
            Color(hex: "FFCC00"),
            Color(hex: "34C759")
        ],
        palette: { _ in
            palette(
                background: "FFF7FA",
                surface: "FFFFFF",
                surfaceElevated: "FFE8F1",
                accent: "FF2D55",
                accentSecondary: "FF9500",
                success: "34C759",
                warning: "FFB800",
                danger: "FF3B30",
                textPrimary: "1D1D1F",
                textSecondary: "6E6E73",
                border: "F5CEDF"
            )
        }
    )

    private static let prideDark = AppTheme(
        id: "pride-dark",
        name: "Pride Dark",
        description: "Contrasti neon arcobaleno per ambienti scuri.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "FF2D55"),
            Color(hex: "BF5AF2"),
            Color(hex: "FFD60A")
        ],
        palette: { _ in
            palette(
                background: "201024",
                surface: "2A1630",
                surfaceElevated: "311B38",
                accent: "FF2D55",
                accentSecondary: "BF5AF2",
                success: "30D158",
                warning: "FFD60A",
                danger: "FF453A",
                textPrimary: "FCE7F3",
                textSecondary: "C084FC",
                border: "3A1F45"
            )
        }
    )

    private static let githubLight = AppTheme(
        id: "github-light",
        name: "GitHub Light",
        description: "Replica il tema \"GitHub Light Default\".",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "F6F8FA"),
            Color(hex: "FFFFFF"),
            Color(hex: "0969DA")
        ],
        palette: { _ in
            palette(
                background: "F6F8FA",
                surface: "FFFFFF",
                surfaceElevated: "EFF2F6",
                accent: "0969DA",
                accentSecondary: "54AEFF",
                success: "1F883D",
                warning: "BF8700",
                danger: "CF222E",
                textPrimary: "1F2328",
                textSecondary: "656D76",
                border: "D0D7DE"
            )
        }
    )

    private static let githubDark = AppTheme(
        id: "github-dark",
        name: "GitHub Dark",
        description: "Ispirato a \"GitHub Dark Default\".",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "0D1117"),
            Color(hex: "161B22"),
            Color(hex: "2F81F7")
        ],
        palette: { _ in
            palette(
                background: "0D1117",
                surface: "161B22",
                surfaceElevated: "1C2128",
                accent: "2F81F7",
                accentSecondary: "6E7681",
                success: "3FB950",
                warning: "D29922",
                danger: "F85149",
                textPrimary: "E6EDF3",
                textSecondary: "A1A7B7",
                border: "30363D"
            )
        }
    )

    private static let unicornLight = AppTheme(
        id: "unicorn-light",
        name: "Unicorn Light",
        description: "Pastelli e colori candy-friendly.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "FF6BD8"),
            Color(hex: "BF5AF2"),
            Color(hex: "A0D7FF")
        ],
        palette: { _ in
            palette(
                background: "FFF0FB",
                surface: "FFFFFF",
                surfaceElevated: "FFE1F7",
                accent: "FF6BD8",
                accentSecondary: "BF5AF2",
                success: "34C759",
                warning: "FFB800",
                danger: "FF375F",
                textPrimary: "2D0F3A",
                textSecondary: "8A4F9F",
                border: "F3B2E5"
            )
        }
    )

    private static let unicornDark = AppTheme(
        id: "unicorn-dark",
        name: "Unicorn Dark",
        description: "Night mode sognante con accenti neon.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "FF6BD8"),
            Color(hex: "A5B4FC"),
            Color(hex: "63E6BE")
        ],
        palette: { _ in
            palette(
                background: "1B1226",
                surface: "241530",
                surfaceElevated: "2E1B3E",
                accent: "FF6BD8",
                accentSecondary: "A5B4FC",
                success: "63E6BE",
                warning: "F4A259",
                danger: "FF4D6D",
                textPrimary: "FFE4FF",
                textSecondary: "D6BCFA",
                border: "3C1F4A"
            )
        }
    )

    private static let solarizedLight = AppTheme(
        id: "solarized-light",
        name: "Solarized Light",
        description: "Il classico tema chiaro di Ethan Schoonover.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "FDF6E3"),
            Color(hex: "EEE8D5"),
            Color(hex: "268BD2")
        ],
        palette: { _ in
            palette(
                background: "FDF6E3",
                surface: "FFFCF0",
                surfaceElevated: "EEE8D5",
                accent: "268BD2",
                accentSecondary: "2AA198",
                success: "859900",
                warning: "B58900",
                danger: "DC322F",
                textPrimary: "3C3B30",
                textSecondary: "657B83",
                border: "E2D7BF"
            )
        }
    )

    private static let solarizedDark = AppTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        description: "Versione dark accuratamente bilanciata.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "002B36"),
            Color(hex: "073642"),
            Color(hex: "B58900")
        ],
        palette: { _ in
            palette(
                background: "002B36",
                surface: "01313F",
                surfaceElevated: "033444",
                accent: "268BD2",
                accentSecondary: "B58900",
                success: "859900",
                warning: "CB4B16",
                danger: "DC322F",
                textPrimary: "E1E8D8",
                textSecondary: "93A1A1",
                border: "0A3947"
            )
        }
    )

    private static let dracula = AppTheme(
        id: "dracula",
        name: "Dracula",
        description: "Tema scuro iconico per dev notturni.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "282A36"),
            Color(hex: "44475A"),
            Color(hex: "BD93F9")
        ],
        palette: { _ in
            palette(
                background: "1F2030",
                surface: "282A36",
                surfaceElevated: "333549",
                accent: "BD93F9",
                accentSecondary: "FF79C6",
                success: "50FA7B",
                warning: "F1FA8C",
                danger: "FF5555",
                textPrimary: "F8F8F2",
                textSecondary: "BFBED2",
                border: "3E4057"
            )
        }
    )

    private static let monokai = AppTheme(
        id: "monokai",
        name: "Monokai",
        description: "Colori saturi in stile Sublime Text.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "272822"),
            Color(hex: "49483E"),
            Color(hex: "F92672")
        ],
        palette: { _ in
            palette(
                background: "1E1F1A",
                surface: "272822",
                surfaceElevated: "333429",
                accent: "F92672",
                accentSecondary: "A6E22E",
                success: "A6E22E",
                warning: "FD971F",
                danger: "F92672",
                textPrimary: "F8F8F2",
                textSecondary: "9DA0A3",
                border: "3E3F32"
            )
        }
    )

    private static let nordLight = AppTheme(
        id: "nord-light",
        name: "Nord Light",
        description: "Toni ghiaccio e accenti blu della palette Nord.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "E5E9F0"),
            Color(hex: "ECEFF4"),
            Color(hex: "5E81AC")
        ],
        palette: { _ in
            palette(
                background: "ECEFF4",
                surface: "FFFFFF",
                surfaceElevated: "E5E9F0",
                accent: "5E81AC",
                accentSecondary: "88C0D0",
                success: "A3BE8C",
                warning: "EBCB8B",
                danger: "BF616A",
                textPrimary: "2E3440",
                textSecondary: "4C566A",
                border: "D8DEE9"
            )
        }
    )

    private static let nordDark = AppTheme(
        id: "nord-dark",
        name: "Nord Dark",
        description: "Versione dark professionale e desaturata.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "2E3440"),
            Color(hex: "3B4252"),
            Color(hex: "88C0D0")
        ],
        palette: { _ in
            palette(
                background: "2E3440",
                surface: "3B4252",
                surfaceElevated: "434C5E",
                accent: "88C0D0",
                accentSecondary: "81A1C1",
                success: "A3BE8C",
                warning: "EBCB8B",
                danger: "BF616A",
                textPrimary: "ECEFF4",
                textSecondary: "D8DEE9",
                border: "4C566A"
            )
        }
    )

    private static let tokyoNight = AppTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        description: "Scuro, neon e ispirato all'omonimo tema VS Code.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "1A1B26"),
            Color(hex: "24283B"),
            Color(hex: "7AA2F7")
        ],
        palette: { _ in
            palette(
                background: "16161E",
                surface: "1A1B26",
                surfaceElevated: "24283B",
                accent: "7AA2F7",
                accentSecondary: "BB9AF7",
                success: "9ECE6A",
                warning: "E0AF68",
                danger: "F7768E",
                textPrimary: "C0CAF5",
                textSecondary: "9AA5CE",
                border: "2A2F45"
            )
        }
    )

    private static let gruvboxLight = AppTheme(
        id: "gruvbox-light",
        name: "Gruvbox Light",
        description: "Look retro caldo con sfondo crema.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "FBF1C7"),
            Color(hex: "EBDBB2"),
            Color(hex: "458588")
        ],
        palette: { _ in
            palette(
                background: "FBF1C7",
                surface: "FFFBE2",
                surfaceElevated: "EBDBB2",
                accent: "458588",
                accentSecondary: "B16286",
                success: "98971A",
                warning: "D79921",
                danger: "CC241D",
                textPrimary: "3C3836",
                textSecondary: "7C6F64",
                border: "E6D3A3"
            )
        }
    )

    private static let eInkDark = AppTheme(
        id: "e-ink-dark",
        name: "E Ink Dark",
        description: "Un tema scuro che simula l'inversione di un display E Ink.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "000000"),
            Color(hex: "1C1C1C"),
            Color(hex: "FFFFFF")
        ],
        palette: { _ in
            palette(
                background: "000000",
                surface: "1C1C1C",
                surfaceElevated: "2C2C2C",
                accent: "FFFFFF",
                accentSecondary: "AAAAAA",
                success: "FFFFFF",
                warning: "FFFFFF",
                danger: "FFFFFF",
                textPrimary: "FFFFFF",
                textSecondary: "888888",
                border: "333333"
            )
        }
    )

    private static let eInkLight = AppTheme(
        id: "e-ink-light",
        name: "E Ink Light",
        description: "Un tema ad alto contrasto che imita un display E Ink.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "F7F7F7"),
            Color(hex: "FFFFFF"),
            Color(hex: "000000")
        ],
        palette: { _ in
            palette(
                background: "F7F7F7",
                surface: "FFFFFF",
                surfaceElevated: "F2F2F2",
                accent: "000000",
                accentSecondary: "555555",
                success: "000000",
                warning: "000000",
                danger: "000000",
                textPrimary: "000000",
                textSecondary: "777777",
                border: "E0E0E0"
            )
        }
    )

    private static let notionDark = AppTheme(
        id: "notion-dark",
        name: "Notion Dark",
        description: "Una versione scura del tema Notion per non affaticare gli occhi.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "191919"),
            Color(hex: "252525"),
            Color(hex: "D4D4D4")
        ],
        palette: { _ in
            palette(
                background: "191919",
                surface: "252525",
                surfaceElevated: "2E2E2E",
                accent: "4B8BFF",
                accentSecondary: "FFA633",
                success: "34D399",
                warning: "FBBF24",
                danger: "F87171",
                textPrimary: "D4D4D4",
                textSecondary: "9B9B9B",
                border: "3A3A3A"
            )
        }
    )

    private static let notionLight = AppTheme(
        id: "notion-light",
        name: "Notion Light",
        description: "Un tema pulito e minimale ispirato a Notion.",
        preferredColorScheme: .light,
        category: .light,
        previewSwatches: [
            Color(hex: "FFFFFF"),
            Color(hex: "F1F1EF"),
            Color(hex: "373530")
        ],
        palette: { _ in
            palette(
                background: "FFFFFF",
                surface: "F7F7F5",
                surfaceElevated: "F1F1EF",
                accent: "3B82F6",
                accentSecondary: "F59E0B",
                success: "22C55E",
                warning: "F97316",
                danger: "EF4444",
                textPrimary: "373530",
                textSecondary: "787774",
                border: "E5E5E3"
            )
        }
    )

    private static let gruvboxDark = AppTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        description: "Palette terrosa con accenti vivaci.",
        preferredColorScheme: .dark,
        category: .dark,
        previewSwatches: [
            Color(hex: "282828"),
            Color(hex: "3C3836"),
            Color(hex: "FABD2F")
        ],
        palette: { _ in
            palette(
                background: "1D2021",
                surface: "282828",
                surfaceElevated: "3C3836",
                accent: "FABD2F",
                accentSecondary: "83A598",
                success: "B8BB26",
                warning: "D79921",
                danger: "FB4934",
                textPrimary: "EBDBB2",
                textSecondary: "BDAE93",
                border: "504945"
            )
        }
    )

    static let available: [AppTheme] = [
        systemTheme,
        xcodeLight,
        xcodeDark,
        vscodeLight,
        vscodeDark,
        prideLight,
        prideDark,
        githubLight,
        githubDark,
        unicornLight,
        unicornDark,
        solarizedLight,
        solarizedDark,
        dracula,
        monokai,
        nordLight,
        nordDark,
        tokyoNight,
        gruvboxLight,
        gruvboxDark,
        notionLight,
        notionDark,
        eInkLight,
        eInkDark
    ]

    static var defaultTheme: AppTheme { systemTheme }

    static var automaticThemes: [AppTheme] {
        available.filter { $0.category == .automatic }
    }

    static var lightThemes: [AppTheme] {
        available.filter { $0.category == .light }
    }

    static var darkThemes: [AppTheme] {
        available.filter { $0.category == .dark }
    }

    static func theme(with id: String?) -> AppTheme {
        guard let id,
              let theme = available.first(where: { $0.id == id }) else {
            // Backwards compatibility for previous plain "light"/"dark" settings.
            if id == "light" {
                return xcodeLight
            }
            if id == "dark" {
                return xcodeDark
            }
            return defaultTheme
        }
        return theme
    }

    private static func palette(
        background: String,
        surface: String,
        surfaceElevated: String,
        accent: String,
        accentSecondary: String,
        success: String,
        warning: String,
        danger: String,
        textPrimary: String,
        textSecondary: String,
        border: String
    ) -> DesignSystem.ColorPalette {
        DesignSystem.ColorPalette(
            background: Color(hex: background),
            surface: Color(hex: surface),
            surfaceElevated: Color(hex: surfaceElevated),
            accent: Color(hex: accent),
            accentSecondary: Color(hex: accentSecondary),
            success: Color(hex: success),
            warning: Color(hex: warning),
            danger: Color(hex: danger),
            destructive: Color(hex: danger),
            textPrimary: Color(hex: textPrimary),
            textSecondary: Color(hex: textSecondary),
            border: Color(hex: border)
        )
    }
}
