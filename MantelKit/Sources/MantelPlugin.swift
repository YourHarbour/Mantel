import AppKit

/// What a Mantel plugin has to provide.
///
/// A plugin is a loadable bundle (`.mantelplugin`) whose `NSPrincipalClass` conforms to this
/// protocol. The host instantiates it once, hands it a `PluginHost`, and calls `activate()`.
public protocol MantelPlugin: AnyObject {

    /// Stable reverse-DNS id. Used for settings storage, so don't change it once shipped.
    static var identifier: String { get }

    /// Shown in the preferences sidebar and the host menu.
    static var displayName: String { get }

    /// One line describing what the plugin does, shown under the name in preferences.
    static var summary: String { get }

    /// SF Symbol name for the preferences toolbar.
    static var symbolName: String { get }

    init(host: PluginHost)

    /// Start doing whatever the plugin does. Called on the main thread.
    func activate()

    /// Stop and release everything. Status items handed out by the host are removed for you.
    func deactivate()

    /// The plugin's pane in Mantel's window, shown when its row in the sidebar is selected.
    /// A plugin that has nothing to configure can return nil and simply won't get a row.
    func makePane() -> NSViewController?
}

public extension MantelPlugin {
    func makePane() -> NSViewController? { nil }
    func deactivate() {}
}
