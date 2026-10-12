import AppKit
import MantelKit

/// Controls the two undocumented globals that decide how much room every status item takes up.
///
/// These live in the "any application" preference domain for the current host — the same place
/// `defaults -currentHost write -globalDomain NSStatusItemSpacing` writes to. Each app reads them
/// when it *creates* its status items, so a change only reaches an app when that app is relaunched;
/// a full logout is what makes it apply everywhere at once.
@objc(SpacingPlugin)
public final class SpacingPlugin: NSObject, MantelPlugin {

    public static let identifier = "com.local.mantel.plugin.spacing"
    public static let displayName = "图标间距"
    public static let summary = "收窄菜单栏图标之间的留白。对所有 App 生效。"
    public static let symbolName = "arrow.left.and.right.square"

    static let spacingKey = "NSStatusItemSpacing"
    static let paddingKey = "NSStatusItemSelectionPadding"

    /// What macOS uses when the keys are absent, measured on this machine.
    static let systemDefaultSpacing = 12
    static let systemDefaultPadding = 12

    private let host: PluginHost
    private let settings: PluginSettings

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: SpacingPlugin.identifier)
        super.init()
    }

    public func activate() {}
    public func deactivate() {}

    // MARK: - The global preferences

    static func read(_ key: String) -> Int? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }

    static func write(_ key: String, _ value: Int?) {
        writeBatch([(key, value)])
    }

    static func writeBatch(_ values: [(String, Int?)]) {
        for (key, value) in values {
            CFPreferencesSetValue(key as CFString, value as CFNumber?, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    static var spacing: Int { read(spacingKey) ?? systemDefaultSpacing }
    static var padding: Int { read(paddingKey) ?? systemDefaultPadding }
    static var isCustomised: Bool { read(spacingKey) != nil || read(paddingKey) != nil }

    static func apply(spacing: Int, padding: Int) {
        writeBatch([(spacingKey, spacing), (paddingKey, padding)])
    }

    // MARK: - Per-app overrides

    /// The values themselves live in each target app's own preference domain — that *is* the
    /// setting, so there is no second copy to keep in sync. All we remember here is the display
    /// name, so an override stays listed (and removable) while its app isn't running.
    private var knownNames: [String: String] {
        get { settings.dictionary("overrideNames") }
        set { settings.set(newValue, for: "overrideNames") }
    }

    func overrideName(for bundleID: String) -> String? {
        guard let stored = knownNames[bundleID] else { return nil }
        // Older builds stored "spacing,padding,name".
        return stored.contains(",") ? String(stored.split(separator: ",").last ?? "") : stored
    }

    var overriddenBundleIDs: [String] { Array(knownNames.keys) }

    func spacing(for bundleID: String) -> Int? {
        MenuBarApps.preference(Self.spacingKey, of: bundleID)
    }

    func padding(for bundleID: String) -> Int? {
        MenuBarApps.preference(Self.paddingKey, of: bundleID)
    }

    /// nil means "follow the global setting" — the key is removed rather than set to a number.
    func setOverride(bundleID: String, name: String, spacing: Int?, padding: Int?) {
        MenuBarApps.setPreferences([(Self.spacingKey, spacing), (Self.paddingKey, padding)], of: bundleID)
        var names = knownNames
        if spacing == nil && padding == nil {
            names.removeValue(forKey: bundleID)
        } else {
            names[bundleID] = name
        }
        knownNames = names
    }

    func clearOverride(bundleID: String, name: String) {
        setOverride(bundleID: bundleID, name: name, spacing: nil, padding: nil)
    }

    static func reset() {
        writeBatch([(spacingKey, nil), (paddingKey, nil)])
    }

    /// Relaunches Mantel. macOS reads the two spacing values once per process, when that process
    /// first touches the status bar — verified by re-creating a status item in place after
    /// changing them and getting pixel-identical results. So a preview needs a real relaunch.
    static func relaunchSelf() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Asks loginwindow to log the user out. macOS puts up its own confirmation, and every
    /// app gets the usual chance to object, so this can still be called off.
    ///
    /// This is the only way to make the new values apply everywhere: each app reads them once,
    /// when it creates its status items, and logging back in is what makes every app do that.
    /// Returns an error message, or nil if the request went through.
    static func requestLogOut() -> String? {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAELogOut),
                                           targetDescriptor: target,
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        do {
            try event.sendEvent(options: [.noReply], timeout: 10)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public func makePane() -> NSViewController? {
        SpacingPane(plugin: self)
    }
}
