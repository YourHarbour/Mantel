import AppKit
import MantelKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let services = HostServices()
    private let manager = PluginManager()
    private var mainWindow: MainWindowController?

    private static let disabledKey = "host.disabledPlugins"

    var disabledPlugins: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.disabledKey) }
    }

    var loadedPlugins: [LoadedPlugin] { manager.plugins }
    var loadFailures: [(url: URL, reason: String)] { manager.failures }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        services.delegate = self
        NSApp.mainMenu = MainMenu.build(appName: "Mantel")

        manager.loadAll(host: services, disabled: disabledPlugins)

        mainWindow = MainWindowController(delegate: self)
        mainWindow?.onClose = { [weak self] in self?.windowClosed() }
        openWindow(selecting: nil)
    }

    /// Closing the window doesn't quit — the plugins are the point of the app, and they keep
    /// running. Mantel just stops being a Dock app until you open the window again.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching Mantel again while it is already running (Spotlight, Launchpad, `open -a`)
    /// brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openWindow(selecting: nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for plugin in manager.plugins where !disabledPlugins.contains(plugin.identifier) {
            plugin.instance.deactivate()
        }
    }

    // MARK: - Plugin enable / disable

    func setPlugin(_ id: String, enabled: Bool) {
        guard let plugin = manager.plugin(withID: id) else { return }
        var disabled = disabledPlugins
        if enabled {
            guard disabled.contains(id) else { return }
            disabled.remove(id)
            disabledPlugins = disabled
            plugin.instance.activate()
        } else {
            guard !disabled.contains(id) else { return }
            disabled.insert(id)
            disabledPlugins = disabled
            plugin.instance.deactivate()
            services.removeAllStatusItems(for: id)
        }
    }

    func isPluginEnabled(_ id: String) -> Bool { !disabledPlugins.contains(id) }

    // MARK: - Window

    /// The Dock tile follows the window: visible while the window is, gone once it is closed.
    /// Minimising doesn't close the window, so a minimised Mantel stays in the Dock like any
    /// other app.
    func openWindow(selecting plugin: String?) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        // The menu bar only shows up once the app is actually frontmost, and switching policy
        // takes a run-loop turn to settle.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow?.show(selecting: plugin)
        }
    }

    private func windowClosed() {
        // Deferred: the window is still closing when windowWillClose fires.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
