import AppKit

/// Services the host offers to plugins.
public protocol PluginHost: AnyObject {

    /// A status item of the plugin's own, kept alive by the host and torn down on deactivate.
    /// Call again with the same `id` to get the same item back.
    func statusItem(id: String, for plugin: String) -> NSStatusItem

    /// Drop a status item the plugin no longer wants.
    func removeStatusItem(id: String, for plugin: String)

    /// Persistent settings, namespaced per plugin.
    func settings(for plugin: String) -> PluginSettings

    /// Autosave names of every status item Mantel itself owns. These are the names macOS uses
    /// for the "NSStatusItem Preferred Position <name>" preference, so a plugin can position them.
    var ownedStatusItemNames: [String] { get }

    /// Bring Mantel's window forward, optionally jumping to a plugin's pane.
    func showWindow(selecting plugin: String?)

    func log(_ message: String, from plugin: String)
}
