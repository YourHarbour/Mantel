import AppKit
import MantelKit
import ServiceManagement

/// The landing pane: what's installed, what's on, and the app-level settings.
final class OverviewPane: NSViewController {

    private weak var delegate: AppDelegate?
    private var container: NSStackView!
    private var loginToggle: NSSwitch!

    init(delegate: AppDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        container = Pane.column([], spacing: 12)
        view = Pane.viewController(content: container).view
        reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loginToggle?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    func reload() {
        guard let delegate else { return }
        for view in container.arrangedSubviews {
            container.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        container.addArrangedSubview(Pane.header("插件"))
        container.addArrangedSubview(Pane.note("每个功能都是一个独立的插件，可以单独开关。关掉之后，它放在菜单栏上的图标会立刻消失。"))

        for plugin in delegate.loadedPlugins {
            let toggle = NSSwitch()
            toggle.state = delegate.isPluginEnabled(plugin.identifier) ? .on : .off
            toggle.target = self
            toggle.action = #selector(togglePlugin(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(plugin.identifier)

            let symbol = NSImageView(image: NSImage(systemSymbolName: plugin.type.symbolName,
                                                    accessibilityDescription: nil)
                                     ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!)
            symbol.contentTintColor = .controlAccentColor
            symbol.widthAnchor.constraint(equalToConstant: 22).isActive = true

            let text = Pane.column([
                Pane.label(plugin.displayName, weight: .semibold),
                Pane.note(plugin.type.summary),
            ], spacing: 2)

            let gap = NSView()
            gap.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: [symbol, text, gap, toggle])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12

            let card = Card(content: row)
            container.addArrangedSubview(card)
            Pane.stretch(card, in: container)
        }

        if delegate.loadedPlugins.isEmpty {
            container.addArrangedSubview(Pane.note("没有找到任何插件。Mantel 自带的三个插件应该在 Mantel.app/Contents/PlugIns 里。"))
        }
        for failure in delegate.loadFailures {
            container.addArrangedSubview(Pane.note("⚠️ \(failure.url.lastPathComponent) 加载失败：\(failure.reason)"))
        }

        let reveal = NSButton(title: "打开插件文件夹", target: self, action: #selector(revealPluginFolder))
        reveal.bezelStyle = .rounded
        container.addArrangedSubview(reveal)
        container.addArrangedSubview(Pane.note("放进这个文件夹的 .mantelplugin 会在下次启动时一起加载。"))

        container.addArrangedSubview(Pane.spacer())
        container.addArrangedSubview(Pane.header("Mantel"))

        loginToggle = NSSwitch()
        loginToggle.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        loginToggle.target = self
        loginToggle.action = #selector(toggleLoginItem)
        container.addArrangedSubview(Pane.row("登录时启动", loginToggle, titleWidth: 120))
        container.addArrangedSubview(Pane.note("""
Mantel 自己不占菜单栏 —— 你在菜单栏上看到的图标都来自插件。

关掉这个窗口不会退出 Mantel：插件照常工作，只是 Dock 里的图标会一并消失。
最小化则和普通 App 一样留在 Dock。想再打开窗口，在聚焦搜索或启动台里点一次
Mantel 就行。
"""))


        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        container.addArrangedSubview(Pane.note("版本 \(version)\n\(Bundle.main.bundleURL.path)"))
    }

    @objc private func togglePlugin(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue else { return }
        delegate?.setPlugin(id, enabled: sender.state == .on)
    }

    @objc private func revealPluginFolder() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Mantel/PlugIns")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改登录项"
            alert.informativeText = "\(error.localizedDescription)\n\n把 Mantel.app 移到「应用程序」文件夹后再试一次。"
            alert.runModal()
        }
        loginToggle.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }
}
