import AppKit
import MantelKit

@objc(OrderingPlugin)
public final class OrderingPlugin: NSObject, MantelPlugin {

    public static let identifier = "com.local.mantel.plugin.ordering"
    public static let displayName = "图标排序"
    public static let summary = "重新排列菜单栏图标的先后顺序。需要辅助功能权限。"
    public static let symbolName = "arrow.left.arrow.right"

    let host: PluginHost
    let settings: PluginSettings

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: OrderingPlugin.identifier)
        super.init()
    }

    public func activate() {}
    public func deactivate() {}

    /// Mantel's own items can be placed without any permission at all: `NSStatusItem` reads a
    /// "preferred position" out of the owning app's own preferences when it is created, and we
    /// are the owning app. Verified working — the value is roughly the distance in points from
    /// the right edge of the screen, and smaller means further right.
    static func positionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    static func position(of autosaveName: String) -> Double? {
        UserDefaults.standard.object(forKey: positionKey(for: autosaveName)) as? Double
    }

    static func setPosition(_ value: Double?, of autosaveName: String) {
        let key = positionKey(for: autosaveName)
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    public func makePane() -> NSViewController? {
        OrderingPane(plugin: self)
    }


}
