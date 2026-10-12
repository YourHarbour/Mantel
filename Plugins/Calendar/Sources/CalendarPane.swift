import AppKit
import EventKit
import MantelKit

final class CalendarPane: NSViewController {

    private weak var plugin: CalendarPlugin?
    private let state = CalendarStateManager.shared

    private var startDayPopup: NSPopUpButton!
    private var showLunarButton: NSButton!
    private var showFestivalsButton: NSButton!
    private var statusLabel: NSTextField!
    private var authButton: NSButton!

    init(plugin: CalendarPlugin) {
        self.plugin = plugin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // Start day popup
        startDayPopup = NSPopUpButton()
        startDayPopup.addItem(withTitle: "星期一（周一为第一列）")
        startDayPopup.addItem(withTitle: "星期日（周日为第一列）")
        startDayPopup.selectItem(at: state.startOnMonday ? 0 : 1)
        startDayPopup.target = self
        startDayPopup.action = #selector(startDayChanged)

        // Show lunar checkbox
        showLunarButton = NSButton(checkboxWithTitle: "在日期格下方显示农历", target: self, action: #selector(lunarChanged))
        showLunarButton.state = state.showLunar ? .on : .off

        // Show festivals checkbox
        showFestivalsButton = NSButton(checkboxWithTitle: "高亮显示传统节日（如中秋、重阳等）", target: self, action: #selector(festivalsChanged))
        showFestivalsButton.state = state.showFestivals ? .on : .off
        showFestivalsButton.isEnabled = state.showLunar

        // Calendar Auth
        statusLabel = Pane.label(calendarStatusText())
        authButton = NSButton(title: "前往系统日历授权", target: self, action: #selector(handleAuthAction))
        authButton.bezelStyle = .rounded
        updateAuthButtonTitle()

        let content = Pane.column([
            Pane.header("显示偏好"),
            Pane.row("一周起始日", startDayPopup),
            Pane.note("控制月历网格第一列是星期一还是星期日。中国大陆习惯通常为周一。"),
            Pane.row("农历小字", showLunarButton),
            Pane.row("节日节气", showFestivalsButton),
            Pane.note("开启后将在每个日期下方标注农历与法定/传统节气节日，并在点击日期时展示详细黄历。"),
            Pane.spacer(),
            Pane.header("系统日历日程同步"),
            Pane.row("当前状态", statusLabel),
            Pane.row("权限管理", authButton),
            Pane.note("Mantel 日历插件可直接同步 macOS 系统日历中的日程安排，并在点击日期时在下方展示列表及下钻详情。"),
        ])

        view = Pane.viewController(content: content).view
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateCalendarAuthStatus()
    }

    @objc private func startDayChanged() {
        state.startOnMonday = (startDayPopup.indexOfSelectedItem == 0)
    }

    @objc private func lunarChanged() {
        state.showLunar = (showLunarButton.state == .on)
        showFestivalsButton.isEnabled = state.showLunar
    }

    @objc private func festivalsChanged() {
        state.showFestivals = (showFestivalsButton.state == .on)
    }

    private func calendarStatusText() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .writeOnly:
                return "✅ 已获完全访问权限"
            case .denied, .restricted:
                return "❌ 未授权或被限制"
            case .notDetermined:
                return "⚠️ 尚未授权"
            @unknown default:
                return "未知状态"
            }
        } else {
            switch status {
            case .authorized:
                return "✅ 已获得系统授权"
            case .denied, .restricted:
                return "❌ 未授权或被限制"
            case .notDetermined:
                return "⚠️ 尚未授权"
            @unknown default:
                return "未知状态"
            }
        }
    }

    private func updateAuthButtonTitle() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized || (status.rawValue == 3 || status.rawValue == 4) {
            authButton.title = "已授权 (点击打开日历)"
        } else if status == .denied || status == .restricted {
            authButton.title = "前往系统设置开启"
        } else {
            authButton.title = "申请日历授权"
        }
    }

    private func updateCalendarAuthStatus() {
        statusLabel.stringValue = calendarStatusText()
        updateAuthButtonTitle()
    }

    @objc private func handleAuthAction() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        } else if status == .notDetermined {
            Task {
                await EventService.shared.requestAccess()
                DispatchQueue.main.async { [weak self] in
                    self?.updateCalendarAuthStatus()
                }
            }
        } else {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }
}
