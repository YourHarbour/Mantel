import AppKit
import MantelKit

/// One row in the sidebar.
struct SidebarEntry {
    let id: String
    let title: String
    let symbol: String
}

/// Mantel's window: a source list on the left, the selected plugin's pane on the right.
final class MainWindowController: NSWindowController {

    static let overviewID = "__overview__"
    private static let lastPaneKey = "host.selectedPane"

    private let split = NSSplitViewController()
    private let sidebar = SidebarViewController()
    private let detail = DetailViewController()
    private var panes: [String: NSViewController] = [:]
    private weak var delegate: AppDelegate?

    /// Fired when the window is closed for real. Minimising doesn't close a window, so this
    /// deliberately doesn't fire for ⌘M or the yellow button.
    var onClose: (() -> Void)?

    init(delegate: AppDelegate) {
        self.delegate = delegate

        var entries = [SidebarEntry(id: Self.overviewID, title: "总览", symbol: "square.grid.2x2")]
        panes[Self.overviewID] = OverviewPane(delegate: delegate)

        for plugin in delegate.loadedPlugins {
            guard let pane = plugin.instance.makePane() else { continue }
            entries.append(SidebarEntry(id: plugin.identifier,
                                        title: plugin.displayName,
                                        symbol: plugin.type.symbolName))
            panes[plugin.identifier] = pane
        }
        sidebar.entries = entries

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: detail))

        let window = NSWindow(contentViewController: split)
        window.title = "Mantel"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 760, height: 520))
        window.minSize = NSSize(width: 660, height: 420)
        window.center()
        window.setFrameAutosaveName("MantelMainWindow")
        super.init(window: window)
        window.delegate = self

        sidebar.onSelect = { [weak self] id in self?.show(id) }

        // Reopen on whichever pane was last in front.
        let remembered = UserDefaults.standard.string(forKey: Self.lastPaneKey)
        show(remembered.flatMap { panes[$0] != nil ? $0 : nil } ?? Self.overviewID)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(selecting plugin: String?) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeKeyAndOrderFront(nil)
        if let plugin, panes[plugin] != nil {
            sidebar.select(plugin)
            show(plugin)
        }
    }

    private func show(_ id: String) {
        guard let pane = panes[id] else { return }
        detail.present(pane)
        sidebar.select(id)
        UserDefaults.standard.set(id, forKey: Self.lastPaneKey)
    }

    /// The overview pane's plugin switches can add or remove panes, so rebuild on demand.
    func refreshOverview() {
        (panes[Self.overviewID] as? OverviewPane)?.reload()
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

// MARK: - Sidebar

final class SidebarViewController: NSViewController {

    var entries: [SidebarEntry] = []
    var onSelect: ((String) -> Void)?

    private var table: NSTableView!

    override func loadView() {
        table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.selectionHighlightStyle = .regular

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        view = scroll
    }

    func select(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard table.selectedRow != index else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
}

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let image = NSImageView(image: NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                                ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!)
        image.contentTintColor = .controlAccentColor
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: entry.title)
        label.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [image, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        onSelect?(entries[row].id)
    }
}

// MARK: - Detail

/// Holds whichever pane is currently selected.
final class DetailViewController: NSViewController {

    private var current: NSViewController?

    override func loadView() {
        view = NSView()
    }

    func present(_ pane: NSViewController) {
        guard current !== pane else { return }
        if let current {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(pane)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pane.view)
        NSLayoutConstraint.activate([
            pane.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pane.view.topAnchor.constraint(equalTo: view.topAnchor),
            pane.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        current = pane
    }
}
