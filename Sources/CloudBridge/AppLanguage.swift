import SwiftUI
import AppKit

extension Color {
    static let bridgeAccent: Color = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.72, green: 0.68, blue: 1.0, alpha: 1.0)
        }
        return NSColor(srgbRed: 0.38, green: 0.22, blue: 0.72, alpha: 1.0)
    })
}

@Observable
final class AppLanguage {
    @MainActor static let shared = AppLanguage()
    static let preferenceKey = "interfaceLanguage"
    // 纯语言代码为主，仅以下语言有地区变体：zh-CN/zh-TW, es-ES/es-MX, fr-FR/fr-CA
    static let supported: [String] = [
        "en", "ca", "cs", "da", "de", "el", "fi", "hi", "hr", "hu", "id", "it",
        "ja", "ko", "ms", "nl", "no", "pl", "ro", "ru", "sk", "sv", "th", "tr",
        "uk", "vi", "ar", "he",
        "zh-CN", "zh-TW",
        "es-ES", "es-MX",
        "fr-FR", "fr-CA",
        "pt-BR", "pt-PT"
    ]
    var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: Self.preferenceKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "system"
        selection = Self.supported.contains(saved) ? saved : "system"
    }

    static func resolved(_ selection: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if supported.contains(selection) { return selection }
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferred).first ?? "en"
    }

    static func isRTL(_ selection: String) -> Bool {
        ["ar", "he"].contains(resolved(selection))
    }

    static func text(_ key: String, selection: String? = nil, bundle: Bundle = .main) -> String {
        let chosen = selection ?? UserDefaults.standard.string(forKey: preferenceKey) ?? "system"
        let code = resolved(chosen)
        let fallback = bundle.path(forResource: "en", ofType: "lproj")
            .flatMap(Bundle.init(path:))?.localizedString(forKey: key, value: key, table: nil) ?? key
        guard let path = bundle.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return fallback }
        return localized.localizedString(forKey: key, value: fallback, table: nil)
    }
}
