import AppKit
import SwiftUI
import MantelKit

@objc(CalendarPlugin)
public final class CalendarPlugin: NSObject, MantelPlugin {

    public static let identifier = "com.local.mantel.plugin.calendar"
    public static let displayName = "日历"
    public static let summary = "在菜单栏显示原生日期，点击弹出类 Windows 交互式日历与日程视图。"
    public static let symbolName = "calendar"

    private let host: PluginHost
    private let settings: PluginSettings

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var active = false

    private static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: CalendarPlugin.identifier)
        super.init()
    }

    // MARK: - Lifecycle

    public func activate() {
        guard !active else { return }
        active = true

        let item = host.statusItem(id: "main", for: Self.identifier)
        self.statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusItemTitle()
        }

        // Listen to day, clock, timezone, and wake changes instead of high-frequency polling
        let nc = NotificationCenter.default
        let obs1 = nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            CalendarHelper.invalidateTodayDependentCache()
            self?.updateStatusItemTitle()
            NotificationCenter.default.post(name: NSNotification.Name("CalendarFlyoutWillOpen"), object: nil)
        }
        let obs2 = nc.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            CalendarHelper.invalidateTodayDependentCache()
            self?.updateStatusItemTitle()
        }
        let obs3 = nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            CalendarHelper.invalidateTodayDependentCache()
            self?.updateStatusItemTitle()
        }
        let obs4 = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            CalendarHelper.invalidateTodayDependentCache()
            self?.updateStatusItemTitle()
        }
        observers = [obs1, obs2, obs3, obs4]

        // Relaxed fallback timer (15 minutes with 60s tolerance)
        let t = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.updateStatusItemTitle()
        }
        t.tolerance = 60
        timer = t
    }

    public func deactivate() {
        guard active else { return }
        active = false
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        popover?.close()
        popover = nil
        host.removeStatusItem(id: "main", for: Self.identifier)
        statusItem = nil
    }

    // MARK: - Lazy Popover

    private func ensurePopover() -> NSPopover {
        if let existing = self.popover { return existing }
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 390, height: 650)
        pop.behavior = .transient
        pop.animates = false

        let flyout = CalendarFlyoutView(
            onPinToDesktop: {
                // Reserved for desktop pinning
            },
            onOpenSettings: { [weak self] in
                self?.host.showWindow(selecting: Self.identifier)
            }
        )
        let hosting = NSHostingController(rootView: flyout)
        hosting.view.wantsLayer = true
        hosting.view.layer?.drawsAsynchronously = true
        pop.contentViewController = hosting
        self.popover = pop
        return pop
    }

    // MARK: - Status Bar Handling

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        button.image = nil
        button.title = Self.statusDateFormatter.string(from: Date())
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(title: "日历偏好设置...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let openCalendarItem = NSMenuItem(title: "打开系统日历", action: #selector(openAppleCalendarAction), keyEquivalent: "")
        openCalendarItem.target = self
        menu.addItem(openCalendarItem)

        menu.addItem(NSMenuItem.separator())

        let mantelItem = NSMenuItem(title: "打开 Mantel...", action: #selector(openMantelAction), keyEquivalent: "m")
        mantelItem.target = self
        menu.addItem(mantelItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func openSettingsAction() {
        host.showWindow(selecting: Self.identifier)
    }

    @objc private func openAppleCalendarAction() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    @objc private func openMantelAction() {
        host.showWindow(selecting: nil)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        let popover = ensurePopover()
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updateStatusItemTitle()
            NotificationCenter.default.post(name: NSNotification.Name("CalendarFlyoutWillOpen"), object: nil)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Preference Pane

    public func makePane() -> NSViewController? {
        CalendarPane(plugin: self)
    }
}
