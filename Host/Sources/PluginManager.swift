import AppKit
import MantelKit

/// One loaded plugin plus the bundle it came from.
struct LoadedPlugin {
    let bundle: Bundle
    let type: MantelPlugin.Type
    let instance: MantelPlugin

    var identifier: String { type.identifier }
    var displayName: String { type.displayName }
}

/// Finds `.mantelplugin` bundles, loads them, and instantiates their principal class.
final class PluginManager {

    private(set) var plugins: [LoadedPlugin] = []
    private(set) var failures: [(url: URL, reason: String)] = []

    /// Built-in plugins ship inside the app; anything dropped in Application Support loads too.
    static var searchPaths: [URL] {
        var paths: [URL] = []
        if let builtIn = Bundle.main.builtInPlugInsURL { paths.append(builtIn) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        paths.append(support.appendingPathComponent("Mantel/PlugIns"))
        return paths
    }

    func loadAll(host: PluginHost, disabled: Set<String>, activate: Bool = true) {
        for directory in PluginManager.searchPaths {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "mantelplugin" {
                load(url, host: host, disabled: disabled, activate: activate)
            }
        }
    }

    private func load(_ url: URL, host: PluginHost, disabled: Set<String>, activate: Bool) {
        guard let bundle = Bundle(url: url) else {
            failures.append((url, "不是有效的 bundle")); return
        }
        do {
            try bundle.loadAndReturnError()
        } catch {
            failures.append((url, error.localizedDescription)); return
        }
        guard let principal = bundle.principalClass else {
            failures.append((url, "Info.plist 里没有 NSPrincipalClass")); return
        }
        guard let type = principal as? MantelPlugin.Type else {
            failures.append((url, "\(principal) 没有实现 MantelPlugin")); return
        }
        guard !plugins.contains(where: { $0.identifier == type.identifier }) else {
            failures.append((url, "id \(type.identifier) 已经加载过了")); return
        }
        let instance = type.init(host: host)
        plugins.append(LoadedPlugin(bundle: bundle, type: type, instance: instance))
        if activate, !disabled.contains(type.identifier) {
            instance.activate()
        }
    }

    func plugin(withID id: String) -> LoadedPlugin? {
        plugins.first { $0.identifier == id }
    }
}
