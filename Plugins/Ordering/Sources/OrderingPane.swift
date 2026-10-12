import AppKit
import MantelKit

final class OrderingPane: NSViewController {

    private let plugin: OrderingPlugin
    private var items: [MenuBarItem] = []
    private var table: NSTableView!
    private var permissionLabel: NSTextField!
    private var permissionButton: NSButton!
    private var applyButton: NSButton!
    private var progress: NSTextField!
    private var ownItemsStack: NSStackView!
    private var diagnostics: NSTextField!
    private var permissionPoll: Timer?
    private var lastTrusted = false
    private let scanQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.local.mantel.ordering.item-scan"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var scanOperation: Operation?

    init(plugin: OrderingPlugin) {
        self.plugin = plugin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        permissionLabel = Pane.label("")
        diagnostics = Pane.note("")
        permissionButton = button("授权…", #selector(requestPermission))
        let settingsButton = button("打开系统设置", #selector(openSettings))

        table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.title = "菜单栏图标（按从左到右排列）"
        column.width = 380
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let moves = NSStackView(views: [
            button("← 往左移", #selector(moveItemLeft)),
            button("往右移 →", #selector(moveItemRight)),
            button("重新扫描", #selector(rescan)),
        ])
        moves.orientation = .horizontal
        moves.spacing = 8

        applyButton = button("应用顺序", #selector(applyOrder))
        applyButton.keyEquivalent = "\r"
        progress = Pane.note("")

        ownItemsStack = Pane.column([], spacing: 8)

        let content = Pane.column([
            Pane.header("辅助功能权限"),
            permissionLabel,
            stack([permissionButton, settingsButton]),
            diagnostics,
            Pane.note("""
排序的原理就是替你按住 ⌘ 把图标拖到位。所以 Mantel 需要这个权限才能读到每个图标
的位置、并代你发送鼠标动作 —— Bartender、Ice 这类工具同样要它。
"""),
            Pane.spacer(),
            Pane.header("排列顺序"),
            Pane.note("选中一行，用下面的按钮挪到想要的位置，再按「应用顺序」。"),
            scroll,
            moves,
            stack([applyButton, progress]),
            Pane.note("应用的过程中 Mantel 会接管鼠标逐个拖动图标，这几秒内请不要动鼠标。"),
            Pane.spacer(),
            Pane.header("Mantel 自己的图标"),
            Pane.note("""
这一栏不需要辅助功能权限。数值越小越靠右，留空表示交给系统决定。

macOS 把它当作「希望待在哪里」而不是精确坐标：实际落点会吸附到可用的位置，
两端也有上限，所以填进去的数和最后的位置不会完全对应。你按住 ⌘ 拖动菜单栏
图标时，系统也会自己往这里写值。改完需要重启 Mantel 才生效。
"""),
            ownItemsStack,
        ])
        view = Pane.viewController(content: content).view
        rebuildOwnItems()
        refreshPermission()
        progress.stringValue = "打开面板后扫描菜单栏图标"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshPermission()
        rescan()
        // Granting happens over in System Settings, with this window still open, so poll for it
        // instead of only checking when the pane is first shown.
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollPermission()
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        permissionPoll?.invalidate()
        permissionPoll = nil
        scanOperation?.cancel()
        scanOperation = nil
    }

    private func pollPermission() {
        let trusted = MenuBarScanner.isTrusted
        guard trusted != lastTrusted else { return }
        refreshPermission()
        if trusted { rescan() }
    }

    // MARK: - Bits of UI

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func rebuildOwnItems() {
        for view in ownItemsStack.arrangedSubviews { ownItemsStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for name in plugin.host.ownedStatusItemNames {
            let field = NSTextField(string: OrderingPlugin.position(of: name).map { "\(Int($0))" } ?? "")
            field.placeholderString = "自动"
            field.identifier = NSUserInterfaceItemIdentifier(name)
            field.target = self
            field.action = #selector(ownPositionChanged(_:))
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            ownItemsStack.addArrangedSubview(Pane.row(name, field, titleWidth: 200))
        }
        if plugin.host.ownedStatusItemNames.isEmpty {
            ownItemsStack.addArrangedSubview(Pane.note("当前没有启用任何带菜单栏图标的插件。"))
        }
    }

    // MARK: - Actions

    private func refreshPermission() {
        let trusted = MenuBarScanner.isTrusted
        lastTrusted = trusted
        permissionLabel.stringValue = trusted ? "✅ 已授权，可以扫描和排序了。" : "⚠️ 还没授权，下面的列表会是空的。"
        permissionButton.isEnabled = !trusted
        applyButton?.isEnabled = trusted
        diagnostics.stringValue = """
        当前副本　\(Bundle.main.bundleURL.path)
        签名标识　\(MenuBarScanner.signingIdentity())

        如果系统设置里明明已经打勾、这里却仍然显示未授权，说明 Mantel 重新构建过、
        签名变了，系统会当成另一个 App。在辅助功能列表里用「−」删掉 Mantel 再重新添加即可。
        """
    }

    @objc private func requestPermission() {
        MenuBarScanner.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshPermission() }
    }

    @objc private func openSettings() { MenuBarScanner.openAccessibilitySettings() }

    @objc private func rescan() {
        scanOperation?.cancel()
        progress.stringValue = MenuBarScanner.isTrusted ? "正在扫描…" : "授权后这里会列出所有菜单栏图标"
        applyButton.isEnabled = false

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            let scannedItems = MenuBarScanner.scan()
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation,
                      !operation.isCancelled,
                      self.scanOperation === operation else { return }
                self.scanOperation = nil
                self.items = scannedItems
                self.table.reloadData()
                self.refreshPermission()
                if !scannedItems.isEmpty {
                    self.progress.stringValue = "扫描到 \(scannedItems.count) 个图标"
                } else {
                    self.progress.stringValue = MenuBarScanner.isTrusted
                        ? "没有扫描到图标"
                        : "授权后这里会列出所有菜单栏图标"
                }
            }
        }
        scanOperation = operation
        scanQueue.addOperation(operation)
    }

    @objc private func moveItemLeft() { move(by: -1) }
    @objc private func moveItemRight() { move(by: 1) }

    private func move(by delta: Int) {
        let row = table.selectedRow
        guard row >= 0, row + delta >= 0, row + delta < items.count else { return }
        items.swapAt(row, row + delta)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: row + delta), byExtendingSelection: false)
    }

    @objc private func applyOrder() {
        let desired = items.map(\.key)
        applyButton.isEnabled = false
        progress.stringValue = "正在拖动，请不要动鼠标…"
        DispatchQueue.global(qos: .userInitiated).async {
            MenuBarScanner.apply(order: desired) { message in
                DispatchQueue.main.async { self.progress.stringValue = message }
            }
            DispatchQueue.main.async {
                self.applyButton.isEnabled = true
                self.progress.stringValue = "排列完成"
                self.rescan()
            }
        }
    }

    @objc private func ownPositionChanged(_ sender: NSTextField) {
        guard let name = sender.identifier?.rawValue else { return }
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        OrderingPlugin.setPosition(text.isEmpty ? nil : Double(text), of: name)
    }
}

extension OrderingPane: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: items[row].label)
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
