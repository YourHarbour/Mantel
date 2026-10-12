import AppKit
import Carbon

/// A thin Swift wrapper around a Text Input Source (TIS) reference.
struct InputSource {
    let ref: TISInputSource
    let id: String
    let localizedName: String
    let languages: [String]

    init?(_ ref: TISInputSource) {
        guard let id = InputSource.string(ref, kTISPropertyInputSourceID) else { return nil }
        self.ref = ref
        self.id = id
        self.localizedName = InputSource.string(ref, kTISPropertyLocalizedName) ?? id
        self.languages = InputSource.stringArray(ref, kTISPropertyInputSourceLanguages)
    }

    var primaryLanguage: String? { languages.first }

    func select() {
        TISSelectInputSource(ref)
    }

    // MARK: - Property access

    static func string(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let p = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    static func stringArray(_ ref: TISInputSource, _ key: CFString) -> [String] {
        guard let p = TISGetInputSourceProperty(ref, key) else { return [] }
        let array = Unmanaged<NSArray>.fromOpaque(p).takeUnretainedValue()
        return array.compactMap { $0 as? String }
    }

    static func bool(_ ref: TISInputSource, _ key: CFString) -> Bool {
        guard let p = TISGetInputSourceProperty(ref, key) else { return false }
        return CFBooleanGetValue(unsafeBitCast(p, to: CFBoolean.self))
    }

    // MARK: - Lookup

    static var current: InputSource? {
        guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return InputSource(ref)
    }

    /// Every enabled keyboard input source the user can actually switch to.
    static func selectable() -> [InputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as NSArray? else { return [] }
        var result: [InputSource] = []
        for case let ref as TISInputSource in list {
            guard string(ref, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String) else { continue }
            guard bool(ref, kTISPropertyInputSourceIsSelectCapable), bool(ref, kTISPropertyInputSourceIsEnabled) else { continue }
            guard let source = InputSource(ref) else { continue }
            result.append(source)
        }
        return result
    }
}
