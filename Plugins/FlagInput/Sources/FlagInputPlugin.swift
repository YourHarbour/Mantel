import AppKit
import Carbon
import MantelKit

@objc(FlagInputPlugin)
public final class FlagInputPlugin: NSObject, MantelPlugin {

    public static let identifier = "com.local.mantel.plugin.flaginput"
    public static let displayName = "输入法国旗"
    public static let summary = "在菜单栏用国旗显示当前输入法，点一下可以切换。"
    public static let symbolName = "flag"

    private let host: PluginHost
    private let settings: PluginSettings
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var lastRenderKey = ""
    private var active = false

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: FlagInputPlugin.identifier)
        super.init()
    }

    // MARK: - Settings

    enum Style: String, CaseIterable {
        case flag, flagAndCode, code
        var title: String {
            switch self {
            case .flag: return "只显示旗帜  🇦🇺"
            case .flagAndCode: return "旗帜 + 代码  🇦🇺 EN"
            case .code: return "只显示代码  EN"
            }
        }
    }

    var style: Style {
        get { Style(rawValue: settings.string("style", default: "flagAndCode")) ?? .flagAndCode }
        set { settings.set(newValue.rawValue, for: "style"); redraw() }
    }
    var fontSize: Double {
        get { settings.double("fontSize", default: 15) }
        set { settings.set(newValue, for: "fontSize"); redraw() }
    }
    var codeFontSize: Double {
        get { settings.double("codeFontSize", default: 11) }
        set { settings.set(newValue, for: "codeFontSize"); redraw() }
    }
    var itemPadding: Double {
        get { settings.double("itemPadding", default: 1) }
        set { settings.set(newValue, for: "itemPadding"); redraw() }
    }
    var verticalOffset: Double {
        get { settings.double("verticalOffset", default: 0) }
        set { settings.set(newValue, for: "verticalOffset"); redraw() }
    }
    var flagOverrides: [String: String] {
        get { settings.dictionary("overrides") }
        set { settings.set(newValue, for: "overrides"); redraw() }
    }
    var codeOverrides: [String: String] {
        get { settings.dictionary("codes") }
        set { settings.set(newValue, for: "codes"); redraw() }
    }

    private func redraw() {
        lastRenderKey = ""
        refresh()
    }

    // MARK: - Lifecycle

    public func activate() {
        guard !active else { return }
        active = true
        let item = host.statusItem(id: "flag", for: Self.identifier)
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(inputSourceChanged),
                           name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                           object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(inputSourceChanged),
                           name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                           object: nil, suspensionBehavior: .deliverImmediately)

        // Safety net in case a notification is missed.
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 1.0
        pollTimer = timer
        redraw()
    }

    public func deactivate() {
        guard active else { return }
        active = false
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        statusItem = nil
        host.removeStatusItem(id: "flag", for: Self.identifier)
    }

    @objc private func inputSourceChanged() {
        refresh()
        // The notification can land a hair before TIS reports the new source.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    // MARK: - Drawing

    private func refresh() {
        guard active, let item = statusItem, let button = item.button else { return }
        let source = InputSource.current
        let flag = FlagMap.flag(for: source, overrides: flagOverrides)
        let code = FlagMap.code(for: source, flag: flag, overrides: codeOverrides)

        let pieces: [StatusItemRenderer.Piece]
        switch style {
        case .flag: pieces = [.init(flag, size: fontSize)]
        case .flagAndCode: pieces = [.init(flag, size: fontSize), .init(code, size: codeFontSize)]
        case .code: pieces = [.init(code, size: fontSize)]   // no flag to sit next to
        }

        let appearance = button.effectiveAppearance
        let key = pieces.map { "\($0.text)@\($0.font.pointSize)" }.joined(separator: "\u{1}")
            + "|\(appearance.name.rawValue)|\(verticalOffset)|\(itemPadding)"
        guard key != lastRenderKey else {
            button.toolTip = source?.localizedName
            return
        }
        lastRenderKey = key
        let image = StatusItemRenderer.image(pieces, appearance: appearance,
                                             gap: fontSize * 0.28,
                                             padding: itemPadding,
                                             verticalOffset: verticalOffset)
        button.image = image
        button.imagePosition = .imageOnly
        item.length = image.size.width   // claim exactly the image's width
        button.toolTip = source?.localizedName
    }

    // MARK: - Menus

    /// The input sources, as switchable menu items for this plugin's own status item menu.
    private func inputSourceItems() -> [NSMenuItem] {
        guard active else { return [] }
        let current = InputSource.current
        return InputSource.selectable().map { source in
            let flag = FlagMap.flag(for: source, overrides: flagOverrides)
            let item = NSMenuItem(title: "\(flag)  \(source.localizedName)",
                                  action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source
            item.state = (source.id == current?.id) ? .on : .off
            return item
        }
    }

    public func makePane() -> NSViewController? {
        FlagInputPane(plugin: self)
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? InputSource else { return }
        source.select()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.refresh() }
    }

    @objc fileprivate func assignFlag(_ sender: NSMenuItem) {
        guard let flag = sender.representedObject as? String, let current = InputSource.current else { return }
        var map = flagOverrides
        map[current.id] = flag
        flagOverrides = map
    }

    @objc fileprivate func resetFlag() {
        guard let current = InputSource.current else { return }
        var map = flagOverrides
        map.removeValue(forKey: current.id)
        flagOverrides = map
    }
}

extension FlagInputPlugin: NSMenuDelegate {

    /// The status item's own menu: switch input source, or restyle the current one.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in inputSourceItems() { menu.addItem(item) }
        menu.addItem(.separator())

        let current = InputSource.current
        let flagMenu = NSMenu()
        for flag in FlagMap.picker {
            let item = NSMenuItem(title: "\(flag)  \(FlagMap.countryCode(of: flag, fallback: ""))",
                                  action: #selector(assignFlag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = flag
            if let current, FlagMap.flag(for: current, overrides: flagOverrides) == flag { item.state = .on }
            flagMenu.addItem(item)
        }
        flagMenu.addItem(.separator())
        let reset = NSMenuItem(title: "恢复默认", action: #selector(resetFlag), keyEquivalent: "")
        reset.target = self
        flagMenu.addItem(reset)

        let root = NSMenuItem(title: "把「\(current?.localizedName ?? "无")」的旗帜改成…", action: nil, keyEquivalent: "")
        root.submenu = flagMenu
        menu.addItem(root)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "打开 Mantel 设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    @objc private func openSettings() {
        host.showWindow(selecting: Self.identifier)
    }
}
