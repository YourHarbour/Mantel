import AppKit

/// A view that lays its children out from the top down. Scroll views are unflipped by default,
/// which would park a short pane at the *bottom* of the scrollable area.
public final class FlippedView: NSView {
    public override var isFlipped: Bool { true }
}

/// A rounded, subtly filled container. Built out of a layer-backed view rather than `NSBox`,
/// because `NSBox.contentView` doesn't propagate the content's auto layout height.
public final class Card: NSView {

    public init(content: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        applyColors()

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

/// Small building blocks so every plugin's pane looks like it came from the same app.
public enum Pane {

    /// How wide text is allowed to get before it wraps.
    static let textWidth: Double = 460

    public static func label(_ text: String, size: Double = 13, weight: NSFont.Weight = .regular,
                             color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.preferredMaxLayoutWidth = textWidth
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    public static func note(_ text: String) -> NSTextField {
        label(text, size: 11, color: .secondaryLabelColor)
    }

    public static func header(_ text: String) -> NSTextField {
        label(text, size: 13, weight: .semibold)
    }

    /// A labelled row: title on the left at a fixed width, control on the right.
    public static func row(_ title: String, _ control: NSView, titleWidth: Double = 130) -> NSView {
        let caption = label(title)
        caption.alignment = .right
        caption.preferredMaxLayoutWidth = titleWidth
        let stack = NSStackView(views: [caption, control])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        caption.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true
        return stack
    }

    public static func column(_ views: [NSView], spacing: Double = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    /// Makes a view span the full width of the column it sits in. A vertical `NSStackView`
    /// otherwise sizes each row to its own intrinsic width.
    public static func stretch(_ view: NSView, in stack: NSStackView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    public static func spacer(_ height: Double = 8) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    /// Wraps a pane's content with standard margins inside a scroll view, so a pane taller than
    /// the window still works.
    public static func viewController(minimumWidth: Double = 440, content: NSView) -> NSViewController {
        let controller = NSViewController()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),

            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            document.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 20),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth),
        ])
        controller.view = scroll
        return controller
    }
}
