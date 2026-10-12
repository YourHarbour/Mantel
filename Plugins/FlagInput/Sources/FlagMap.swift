import Foundation

/// Maps an input source to the flag emoji shown in the menu bar.
enum FlagMap {

    /// Explicit input-source-ID -> flag. Anything here can be overridden in config.json.
    static let defaults: [String: String] = [
        // --- 中文 简体 ---
        "com.apple.inputmethod.SCIM.ITABC": "🇨🇳",        // 简体拼音
        "com.apple.inputmethod.SCIM.Shuangpin": "🇨🇳",    // 简体双拼
        "com.apple.inputmethod.SCIM.WBX": "🇨🇳",          // 五笔型
        "com.apple.inputmethod.SCIM.WBH": "🇨🇳",          // 五笔画
        "com.apple.inputmethod.SCIM.Pinyin": "🇨🇳",

        // --- 中文 繁体 ---
        "com.apple.inputmethod.TCIM.Pinyin": "🇨🇳",
        "com.apple.inputmethod.TCIM.Zhuyin": "🇨🇳",
        "com.apple.inputmethod.TCIM.ZhuyinEten": "🇨🇳",
        "com.apple.inputmethod.TCIM.Cangjie": "🇨🇳",
        "com.apple.inputmethod.TCIM.Sucheng": "🇨🇳",
        "com.apple.inputmethod.TCIM.Shuangpin": "🇨🇳",
        "com.apple.inputmethod.TCIM.WBH": "🇨🇳",
        // --- 粤语 ---
        "com.apple.inputmethod.TCIM.Jyutping": "🇭🇰",
        "com.apple.inputmethod.TCIM.Cantonese": "🇭🇰",

        // --- English ---
        "com.apple.keylayout.ABC": "🇦🇺",        // 通用英文布局 -> 默认澳洲
        "com.apple.keylayout.US": "🇺🇸",
        "com.apple.keylayout.USExtended": "🇺🇸",
        "com.apple.keylayout.US-International-PC": "🇺🇸",
        "com.apple.keylayout.Australian": "🇦🇺",
        "com.apple.keylayout.British": "🇬🇧",
        "com.apple.keylayout.British-PC": "🇬🇧",
        "com.apple.keylayout.Irish": "🇮🇪",
        "com.apple.keylayout.IrishExtended": "🇮🇪",
        "com.apple.keylayout.Canadian": "🇨🇦",
        "com.apple.keylayout.CanadianFrench": "🇨🇦",

        // --- 其他常见 ---
        "com.apple.keylayout.French": "🇫🇷",
        "com.apple.keylayout.German": "🇩🇪",
        "com.apple.keylayout.Spanish": "🇪🇸",
        "com.apple.keylayout.Italian": "🇮🇹",
        "com.apple.keylayout.Russian": "🇷🇺",
    ]

    /// Fallback by primary language when the ID is unknown.
    static let byLanguage: [String: String] = [
        "zh-Hans": "🇨🇳", "zh-Hant": "🇨🇳", "yue": "🇭🇰", "zh": "🇨🇳",
        "en": "🇦🇺", "ja": "🇯🇵", "ko": "🇰🇷", "fr": "🇫🇷", "de": "🇩🇪",
        "es": "🇪🇸", "it": "🇮🇹", "ru": "🇷🇺", "pt": "🇵🇹", "nl": "🇳🇱",
        "sv": "🇸🇪", "no": "🇳🇴", "da": "🇩🇰", "fi": "🇫🇮", "pl": "🇵🇱",
        "tr": "🇹🇷", "ar": "🇸🇦", "he": "🇮🇱", "hi": "🇮🇳", "th": "🇹🇭",
        "vi": "🇻🇳", "id": "🇮🇩", "uk": "🇺🇦", "cs": "🇨🇿", "el": "🇬🇷",
    ]

    /// Short codes that should not follow the flag's country code.
    static let codeByLanguage: [String: String] = [
        "en": "EN",
    ]

    /// Flags offered in the "change flag" submenu.
    static let picker: [String] = [
        "🇨🇳", "🇭🇰", "🇺🇸", "🇬🇧", "🇦🇺", "🇳🇿", "🇨🇦", "🇮🇪",
        "🇯🇵", "🇰🇷", "🇫🇷", "🇩🇪", "🇪🇸", "🇮🇹", "🇷🇺", "🇸🇬", "🇲🇾",
    ]

    static let unknown = "⌨️"

    /// Resolve the flag for a source: user override -> built-in table -> language -> keyboard glyph.
    static func flag(for source: InputSource?, overrides: [String: String]) -> String {
        guard let source else { return unknown }
        if let custom = overrides[source.id], !custom.isEmpty { return custom }
        if let known = defaults[source.id] { return known }
        for language in source.languages {
            if let byExact = byLanguage[language] { return byExact }
            let base = String(language.prefix(while: { $0 != "-" }))
            if let byBase = byLanguage[base] { return byBase }
        }
        return unknown
    }

    /// Short code shown next to (or instead of) the flag.
    /// user override -> language table -> the flag's own country code.
    static func code(for source: InputSource?, flag: String, overrides: [String: String]) -> String {
        if let source, let custom = overrides[source.id], !custom.isEmpty { return custom }
        if let source {
            for language in source.languages {
                if let known = codeByLanguage[language] { return known }
                let base = String(language.prefix(while: { $0 != "-" }))
                if let known = codeByLanguage[base] { return known }
            }
        }
        return countryCode(of: flag, fallback: source?.localizedName ?? "")
    }

    /// "🇦🇺" -> "AU". Regional indicator pairs decode straight back to ASCII letters.
    static func countryCode(of flag: String, fallback: String) -> String {
        let letters = flag.unicodeScalars.compactMap { scalar -> Character? in
            guard scalar.value >= 0x1F1E6, scalar.value <= 0x1F1FF else { return nil }
            return Character(UnicodeScalar(scalar.value - 0x1F1E6 + 65)!)
        }
        if letters.isEmpty {
            return String(fallback.prefix(2)).uppercased()
        }
        return String(letters)
    }
}
