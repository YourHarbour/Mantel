import Foundation

/// A small typed wrapper over `UserDefaults`, with every key prefixed by the plugin's id so two
/// plugins can both use a key called "style" without colliding.
public final class PluginSettings {

    private let prefix: String
    private let defaults: UserDefaults

    public init(pluginID: String, defaults: UserDefaults = .standard) {
        self.prefix = "plugin.\(pluginID)."
        self.defaults = defaults
    }

    private func key(_ name: String) -> String { prefix + name }

    public func string(_ name: String, default fallback: String) -> String {
        defaults.string(forKey: key(name)) ?? fallback
    }

    public func double(_ name: String, default fallback: Double) -> Double {
        defaults.object(forKey: key(name)) as? Double ?? fallback
    }

    public func int(_ name: String, default fallback: Int) -> Int {
        defaults.object(forKey: key(name)) as? Int ?? fallback
    }

    public func bool(_ name: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    public func dictionary(_ name: String) -> [String: String] {
        defaults.dictionary(forKey: key(name)) as? [String: String] ?? [:]
    }

    public func stringArray(_ name: String) -> [String] {
        defaults.stringArray(forKey: key(name)) ?? []
    }

    public func set(_ value: Any?, for name: String) {
        if let value {
            defaults.set(value, forKey: key(name))
        } else {
            defaults.removeObject(forKey: key(name))
        }
    }
}
