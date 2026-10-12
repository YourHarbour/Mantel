import AppKit
import MantelKit

final class SpacingPane: NSViewController {

    private let plugin: SpacingPlugin
    private var spacingSlider: NSSlider!
    private var paddingSlider: NSSlider!
    private var readout: NSTextField!
    private var status: NSTextField!
    private var appList: NSStackView!
    private var permissionNote: NSTextField!
    private let scanQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.local.mantel.spacing.app-scan"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var scanOperation: Operation?
    private var syncWorkItem: DispatchWorkItem?

    init(plugin: SpacingPlugin) {
        self.plugin = plugin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        spacingSlider = slider(value: Double(SpacingPlugin.spacing))
        paddingSlider = slider(value: Double(SpacingPlugin.padding))
        readout = Pane.label("")
        status = Pane.note("")

        let presets = NSStackView(views: [
            button("紧凑 (4)", #selector(presetTight)),
            button("很紧 (2)", #selector(presetTighter)),
            button("系统默认", #selector(resetToSystem)),
        ])
        presets.orientation = .horizontal
        presets.spacing = 8

        let logOut = NSButton(title: "注销并重新登录…", target: self, action: #selector(logOutNow))
        logOut.bezelStyle = .rounded
        logOut.keyEquivalent = "\r"

        let preview = NSButton(title: "只重启 Mantel 预览", target: self, action: #selector(previewOnMantel))
        preview.bezelStyle = .rounded

        let actions = NSStackView(views: [logOut, preview])
        actions.orientation = .horizontal
        actions.spacing = 8

        appList = Pane.column([], spacing: 8)
        permissionNote = Pane.note("")

        let content = Pane.column([
            Pane.header("所有 App"),
            Pane.note("这两个值决定每个菜单栏图标占多宽。这里设的是全局默认值，下面可以给单个 App 单独调。"),
            Pane.row("图标间距", spacingSlider),
            Pane.row("点击留白", paddingSlider),
            Pane.note("「点击留白」是图标周围可以点到的范围。设得太小图标会很难点中。"),
            Pane.row("", readout),
            presets,
            status,

            Pane.spacer(),
            Pane.header("单独设置"),
            Pane.note("""
有些 App（iStat Menus 这类要在图标里画图表和数字的）宽度在创建图标时就定死了，
全局值压太小会把内容裁掉一截。给它单独调大一点即可 —— App 自己的设置优先于全局设置。

注意菜单栏图标常常属于 App 的辅助进程而不是主程序，下面列的就是真正持有图标的那个进程。
"""),
            permissionNote,
            appList,

            Pane.spacer(),
            Pane.header("让新设置生效"),
            Pane.note("""
这两个值是每个 App 在「启动时」读一次的，所以改完之后已经在运行的 App 不会跟着变，
哪怕它重新画了自己的图标也一样。重新登录一次让所有 App 重新启动，新设置才会全部用上；
只改了某一个 App 的话，把那个 App 重开一次就够了。
"""),
            actions,
            Pane.note("""
「只重启 Mantel 预览」会重开一次 Mantel，让你先在自己的图标上看看这个宽度合不合适。

参考：系统默认时 Mantel 和右边邻居之间是 21pt，设成 2 / 4 后是 14pt，全设成 0 是 13pt。
再往下压省不了多少，却会让图标不好点，建议留 4~6。
"""),
        ])
        view = Pane.viewController(content: content).view
        permissionNote.stringValue = "正在扫描菜单栏 App…"
        refresh()
    }

    private func slider(value: Double) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 16,
                              target: self, action: #selector(sliderMoved))
        slider.numberOfTickMarks = 17
        slider.allowsTickMarkValuesOnly = true
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return slider
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    /// Written straight away, the way a System Settings slider behaves. Nothing visible happens
    /// until apps re-create their status items, which is what the two buttons below are for.
    override func viewDidAppear() {
        super.viewDidAppear()
        reloadApps()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        scanOperation?.cancel()
        scanOperation = nil
    }

    // MARK: - Per-app rows

    /// Every app that owns menu bar items, plus any app we've already overridden that happens
    /// not to be running right now.
    private func reloadApps() {
        scanOperation?.cancel()
        permissionNote.isHidden = false
        permissionNote.stringValue = MenuBarApps.isTrusted
            ? "正在扫描菜单栏 App…"
            : "正在读取运行中的 App…"

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            let apps = MenuBarApps.list()
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation,
                      !operation.isCancelled,
                      self.scanOperation === operation else { return }
                self.scanOperation = nil
                self.applyApps(apps)
            }
        }
        scanOperation = operation
        scanQueue.addOperation(operation)
    }

    private func applyApps(_ scannedApps: [MenuBarApp]) {
        for view in appList.arrangedSubviews {
            appList.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        var apps = scannedApps
        let listed = Set(apps.map(\.bundleID))
        for bundleID in plugin.overriddenBundleIDs where !listed.contains(bundleID) {
            apps.append(MenuBarApp(name: plugin.overrideName(for: bundleID) ?? bundleID,
                                   bundleID: bundleID, itemCount: nil))
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let trusted = MenuBarApps.isTrusted
        permissionNote.stringValue = trusted ? "" :
            "没有辅助功能权限，下面列的是所有正在运行的 App，分不出哪些真的有菜单栏图标。"
        permissionNote.isHidden = trusted

        for app in apps {
            appList.addArrangedSubview(row(for: app))
            Pane.stretch(appList.arrangedSubviews.last!, in: appList)
        }
        if apps.isEmpty {
            appList.addArrangedSubview(Pane.note("没有找到任何带菜单栏图标的 App。"))
        }
    }

    private func row(for app: MenuBarApp) -> NSView {
        let title = Pane.label(app.label, weight: .semibold)
        let subtitle = Pane.note(app.bundleID)
        let text = Pane.column([title, subtitle], spacing: 2)

        let gap = NSView()
        gap.setContentHuggingPriority(.init(1), for: .horizontal)

        let spacing = valuePopup(app: app, key: SpacingPlugin.spacingKey,
                                 current: plugin.spacing(for: app.bundleID))
        let padding = valuePopup(app: app, key: SpacingPlugin.paddingKey,
                                 current: plugin.padding(for: app.bundleID))

        let controls = NSStackView(views: [
            Pane.note("间距"), spacing, Pane.note("留白"), padding,
        ])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6

        let row = NSStackView(views: [text, gap, controls])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return Card(content: row)
    }

    /// "跟随全局" plus 0…16. Follow-global removes the key rather than writing a number.
    private func valuePopup(app: MenuBarApp, key: String, current: Int?) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "跟随全局")
        popup.lastItem?.tag = -1
        for value in 0...16 {
            popup.addItem(withTitle: "\(value)")
            popup.lastItem?.tag = value
        }
        popup.selectItem(withTag: current ?? -1)
        popup.target = self
        popup.action = #selector(valueChanged(_:))
        popup.identifier = NSUserInterfaceItemIdentifier("\(key)\u{1}\(app.bundleID)\u{1}\(app.name)")
        popup.widthAnchor.constraint(equalToConstant: 96).isActive = true
        return popup
    }

    @objc private func valueChanged(_ sender: NSPopUpButton) {
        let parts = (sender.identifier?.rawValue ?? "").components(separatedBy: "\u{1}")
        guard parts.count == 3 else { return }
        let (key, bundleID, name) = (parts[0], parts[1], parts[2])
        let chosen: Int? = sender.selectedTag() == -1 ? nil : sender.selectedTag()

        let spacing = key == SpacingPlugin.spacingKey ? chosen : plugin.spacing(for: bundleID)
        let padding = key == SpacingPlugin.paddingKey ? chosen : plugin.padding(for: bundleID)
        plugin.setOverride(bundleID: bundleID, name: name, spacing: spacing, padding: padding)

        status.stringValue = (spacing == nil && padding == nil)
            ? "\(name) 已改回跟随全局。重开这个 App 之后生效。"
            : "\(name) 已单独设置。重开这个 App 之后生效。"
    }

    @objc private func sliderMoved() {
        refresh()
        syncWorkItem?.cancel()
        let spacing = spacingSlider.integerValue
        let padding = paddingSlider.integerValue
        let item = DispatchWorkItem {
            SpacingPlugin.apply(spacing: spacing, padding: padding)
        }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func applyImmediate() {
        syncWorkItem?.cancel()
        syncWorkItem = nil
        SpacingPlugin.apply(spacing: spacingSlider.integerValue, padding: paddingSlider.integerValue)
        refresh()
    }

    @objc private func presetTight() {
        spacingSlider.integerValue = 4; paddingSlider.integerValue = 4; applyImmediate()
    }

    @objc private func presetTighter() {
        spacingSlider.integerValue = 2; paddingSlider.integerValue = 4; applyImmediate()
    }

    @objc private func resetToSystem() {
        syncWorkItem?.cancel()
        syncWorkItem = nil
        SpacingPlugin.reset()
        spacingSlider.integerValue = SpacingPlugin.systemDefaultSpacing
        paddingSlider.integerValue = SpacingPlugin.systemDefaultPadding
        refresh()
        status.stringValue = "已恢复系统默认。重新登录后所有图标恢复原状。"
    }

    @objc private func previewOnMantel() {
        SpacingPlugin.relaunchSelf()
    }

    @objc private func logOutNow() {
        let alert = NSAlert()
        alert.messageText = "现在注销并重新登录？"
        alert.informativeText = """
        所有 App 都会退出，没保存的东西会丢失。重新登录之后，\
        菜单栏上所有图标都会用上新的间距（\(spacingSlider.integerValue) / \(paddingSlider.integerValue)）。

        macOS 还会再确认一次，那时也可以取消。
        """
        alert.addButton(withTitle: "注销")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let failure = SpacingPlugin.requestLogOut() {
            let problem = NSAlert()
            problem.messageText = "没能发出注销请求"
            problem.informativeText = "\(failure)\n\n手动注销一样可以：苹果菜单 →「注销」。"
            problem.runModal()
        }
    }

    private func refresh() {
        readout.stringValue = "间距 \(spacingSlider.integerValue) · 点击留白 \(paddingSlider.integerValue)"
        status.stringValue = SpacingPlugin.isCustomised
            ? "已保存。重新登录后所有图标生效。"
            : "当前使用系统默认值。"
    }
}
