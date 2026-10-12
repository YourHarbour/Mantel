import AppKit

// `Mantel --selftest` loads every plugin bundle exactly the way the running app does, reports
// what came back, and exits. Handy after a build, and it needs no window server.
if CommandLine.arguments.contains("--selftest") {
    let services = HostServices()
    let manager = PluginManager()
    print("搜索路径:")
    for path in PluginManager.searchPaths { print("  \(path.path)") }
    let live = CommandLine.arguments.contains("--live")
    manager.loadAll(host: services, disabled: [], activate: live)
    print("\n加载成功 \(manager.plugins.count) 个:")
    for plugin in manager.plugins {
        print("  ✓ \(plugin.displayName)  [\(plugin.identifier)]  \(type(of: plugin.instance))")
        print("      \(plugin.type.summary)")
        print("      " + (plugin.instance.makePane() != nil ? "有设置面板" : "无设置面板"))
    }
    if live {
        // Give the plugins a run-loop turn so timers and first draws happen.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        print("\n菜单栏图标:")
        for line in services.describeStatusItems() { print("  \(line)") }
    }
    if !manager.failures.isEmpty {
        print("\n加载失败 \(manager.failures.count) 个:")
        for failure in manager.failures { print("  ✗ \(failure.url.lastPathComponent): \(failure.reason)") }
    }
    exit(manager.failures.isEmpty && !manager.plugins.isEmpty ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // AppDelegate drops to .accessory when the window closes
app.run()
