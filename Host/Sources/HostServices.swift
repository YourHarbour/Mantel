import AppKit
import MantelKit

/// The host side of `PluginHost`: hands out status items, settings, and menu rebuilds.
final class HostServices: PluginHost {

    weak var delegate: AppDelegate?

    private var statusItems: [String: NSStatusItem] = [:]
    private var settingsStores: [String: PluginSettings] = [:]

    private func key(_ plugin: String, _ id: String) -> String { "\(plugin)/\(id)" }

    func statusItem(id: String, for plugin: String) -> NSStatusItem {
        let compound = key(plugin, id)
        if let existing = statusItems[compound] { return existing }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Lets macOS remember the position if the user ⌘-drags it, and lets the Ordering
        // plugin set it explicitly.
        item.autosaveName = compound
        statusItems[compound] = item
        return item
    }

    func removeStatusItem(id: String, for plugin: String) {
        let compound = key(plugin, id)
        if let item = statusItems.removeValue(forKey: compound) {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    func removeAllStatusItems(for plugin: String) {
        for compound in statusItems.keys where compound.hasPrefix("\(plugin)/") {
            if let item = statusItems.removeValue(forKey: compound) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
    }

    /// Autosave names of every item Mantel owns, for the Ordering plugin.
    var ownedStatusItemNames: [String] { statusItems.keys.sorted() }

    /// Used by `--selftest --live` to confirm plugins really put something in the menu bar.
    func describeStatusItems() -> [String] {
        statusItems.sorted { $0.key < $1.key }.map { name, item in
            let content: String
            if let size = item.button?.image?.size {
                content = String(format: "图像 %.0f×%.0f", size.width, size.height)
            } else if let title = item.button?.title, !title.isEmpty {
                content = "文字 \(title)"
            } else {
                content = "空的"
            }
            return String(format: "%@  length=%.1f  %@  visible=%@",
                          name, item.length, content, item.isVisible ? "是" : "否")
        }
    }

    func settings(for plugin: String) -> PluginSettings {
        if let existing = settingsStores[plugin] { return existing }
        let store = PluginSettings(pluginID: plugin)
        settingsStores[plugin] = store
        return store
    }

    func showWindow(selecting plugin: String?) {
        delegate?.openWindow(selecting: plugin)
    }

    func log(_ message: String, from plugin: String) {
        NSLog("[%@] %@", plugin, message)
    }
}
