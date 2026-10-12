import AppKit
import MantelKit

final class FlagInputPane: NSViewController {

    private let plugin: FlagInputPlugin
    private var stylePopup: NSPopUpButton!
    private var flagSize: NSSlider!
    private var codeSize: NSSlider!
    private var padding: NSSlider!
    private var offset: NSSlider!
    private var preview: NSImageView!
    private var currentLabel: NSTextField!

    init(plugin: FlagInputPlugin) {
        self.plugin = plugin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        stylePopup = NSPopUpButton()
        for style in FlagInputPlugin.Style.allCases { stylePopup.addItem(withTitle: style.title) }
        stylePopup.selectItem(at: FlagInputPlugin.Style.allCases.firstIndex(of: plugin.style) ?? 0)
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)

        flagSize = slider(min: 10, max: 22, value: plugin.fontSize, action: #selector(flagSizeChanged))
        codeSize = slider(min: 8, max: 18, value: plugin.codeFontSize, action: #selector(codeSizeChanged))
        padding = slider(min: 0, max: 8, value: plugin.itemPadding, action: #selector(paddingChanged))
        offset = slider(min: -4, max: 4, value: plugin.verticalOffset, action: #selector(offsetChanged))

        preview = NSImageView()
        preview.imageScaling = .scaleNone
        let previewBox = Card(content: preview,
                              insets: NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10))

        currentLabel = Pane.note("")

        let content = Pane.column([
            Pane.header("菜单栏显示"),
            Pane.row("样式", stylePopup),
            Pane.row("旗帜大小", flagSize),
            Pane.row("代码大小", codeSize),
            Pane.note("""
「代码」指旗帜旁边那两个字母：英语一律是 EN，靠旗帜区分澳、英、美。
选「只显示代码」时没有旗帜作参照，字号用的是上面的「旗帜大小」。
"""),
            Pane.row("左右留白", padding),
            Pane.note("图标左右两侧各留多少空白。调小可以让它在菜单栏上更省地方。"),
            Pane.row("上下微调", offset),
            Pane.row("预览", previewBox),
            Pane.note("旗帜和代码默认就对齐了菜单栏的中线，「上下微调」一般不用动。"),
            Pane.spacer(),
            Pane.header("当前输入法"),
            currentLabel,
            Pane.note("""
想给某个输入法换一面旗帜：点菜单栏上的旗子 →「把…的旗帜改成」。
改动只作用于当时正在使用的那个输入法，其他输入法不受影响。
"""),
        ])
        view = Pane.viewController(content: content).view
        updateEnabledState()
        updatePreview()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updatePreview()
    }

    private func slider(min: Double, max: Double, value: Double, action: Selector) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.numberOfTickMarks = Int(max - min) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return slider
    }

    @objc private func styleChanged() {
        plugin.style = FlagInputPlugin.Style.allCases[stylePopup.indexOfSelectedItem]
        updateEnabledState()
        updatePreview()
    }

    /// Grey out the controls the current style doesn't use.
    private func updateEnabledState() {
        codeSize.isEnabled = (plugin.style == .flagAndCode)
    }

    @objc private func flagSizeChanged() {
        plugin.fontSize = flagSize.doubleValue
        updatePreview()
    }

    @objc private func codeSizeChanged() {
        plugin.codeFontSize = codeSize.doubleValue
        updatePreview()
    }

    @objc private func paddingChanged() {
        plugin.itemPadding = padding.doubleValue
        updatePreview()
    }

    @objc private func offsetChanged() {
        plugin.verticalOffset = offset.doubleValue
        updatePreview()
    }

    private func updatePreview() {
        let source = InputSource.current
        let flag = FlagMap.flag(for: source, overrides: plugin.flagOverrides)
        let code = FlagMap.code(for: source, flag: flag, overrides: plugin.codeOverrides)
        let pieces: [StatusItemRenderer.Piece]
        switch plugin.style {
        case .flag: pieces = [.init(flag, size: plugin.fontSize)]
        case .flagAndCode: pieces = [.init(flag, size: plugin.fontSize), .init(code, size: plugin.codeFontSize)]
        case .code: pieces = [.init(code, size: plugin.fontSize)]
        }
        preview.image = StatusItemRenderer.image(pieces, appearance: view.effectiveAppearance,
                                                 gap: plugin.fontSize * 0.28,
                                                 padding: plugin.itemPadding,
                                                 verticalOffset: plugin.verticalOffset)
        currentLabel.stringValue = source.map { "\(flag)  \($0.localizedName)\n\($0.id)" } ?? "读不到当前输入法"
    }
}
