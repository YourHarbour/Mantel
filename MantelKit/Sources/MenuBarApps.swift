import AppKit
import ApplicationServices

/// A running application that puts something in the menu bar.
public struct MenuBarApp: Hashable, Sendable {
    public let name: String
    public let bundleID: String
    /// How many menu bar items it owns, or nil when we couldn't tell (no accessibility permission).
    public let itemCount: Int?

    public init(name: String, bundleID: String, itemCount: Int?) {
        self.name = name
        self.bundleID = bundleID
        self.itemCount = itemCount
    }

    public var label: String {
        guard let itemCount else { return name }
        return "\(name)（\(itemCount) 个图标）"
    }
}

public enum MenuBarApps {

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// With the accessibility permission, exactly the apps that own menu bar items. Without it,
    /// every running app that plausibly could — the caller still gets a usable list, just longer.
    public static func list() -> [MenuBarApp] {
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier != nil && $0.activationPolicy != .prohibited
        }

        guard AXIsProcessTrusted() else {
            return running
                .map { MenuBarApp(name: $0.localizedName ?? $0.bundleIdentifier!,
                                  bundleID: $0.bundleIdentifier!, itemCount: nil) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        var found: [MenuBarApp] = []
        for app in running {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString,
                                                &extras) == .success, let extras else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString,
                                                &children) == .success,
                  let items = children as? [AXUIElement], !items.isEmpty else { continue }
            found.append(MenuBarApp(name: app.localizedName ?? app.bundleIdentifier!,
                                    bundleID: app.bundleIdentifier!, itemCount: items.count))
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads a preference out of another application's own domain.
    ///
    /// Menu bar spacing is looked up through the normal preference chain, and an application's
    /// own domain is consulted before the global one — so a value written here overrides the
    /// system-wide setting for that one app. Verified by measurement: with the global value at 0,
    /// writing 20 into an app's domain widened its item by exactly 20px on both sides.
    public static func preference(_ key: String, of bundleID: String) -> Int? {
        CFPreferencesCopyValue(key as CFString, bundleID as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int
    }

    public static func setPreference(_ key: String, _ value: Int?, of bundleID: String) {
        setPreferences([(key, value)], of: bundleID)
    }

    public static func setPreferences(_ values: [(String, Int?)], of bundleID: String) {
        for (key, value) in values {
            CFPreferencesSetValue(key as CFString, value as CFNumber?, bundleID as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
