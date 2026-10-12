import AppKit
import MantelKit

@objc(HelloPlugin)
public final class HelloPlugin: NSObject, MantelPlugin {

    public static let identifier  = "com.example.hello"
    public static let displayName = "打招呼"
    public static let summary     = "示例插件。"
    public static let symbolName  = "hand.wave"

    private let host: PluginHost
    private let settings: PluginSettings

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: HelloPlugin.identifier)
        super.init()
    }

    public func activate() {
        let item = host.statusItem(id: "main", for: Self.identifier)
        item.button?.title = "👋"
    }

    public func deactivate() {
        host.removeStatusItem(id: "main", for: Self.identifier)
    }

    public func makePane() -> NSViewController? {
        Pane.viewController(content: Pane.column([
            Pane.header("打招呼"),
            Pane.note("这一页会出现在 Mantel 侧栏里。"),
        ]))
    }
}
