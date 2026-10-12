import AppKit
import CoreText

/// Renders menu bar titles as images with each piece centred on its own *ink*.
///
/// `NSStatusItem.attributedTitle` centres the font's line box (ascent + descent) rather than the
/// glyphs, which parks the content about 1.25pt above every other item in the menu bar. Mixing an
/// emoji with letters makes it worse: they share a baseline, and emoji artwork dips below it, so
/// the letters end up sitting lower than the flag. Measuring real glyph bounds and centring each
/// piece independently fixes both.
public enum StatusItemRenderer {

    public struct Piece {
        public let text: String
        public let font: NSFont
        public init(_ text: String, size: Double) {
            self.text = text
            self.font = NSFont.systemFont(ofSize: size)
        }
    }

    /// Ink (glyph path) bounds relative to the baseline origin.
    private static func inkBounds(_ line: CTLine) -> CGRect {
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if ink.isNull || ink.isEmpty {
            return CTLineGetBoundsWithOptions(line, [])   // bitmap-only glyphs report no path
        }
        return ink
    }

    public static func image(_ pieces: [Piece],
                             appearance: NSAppearance,
                             gap: Double,
                             padding: Double,
                             verticalOffset: Double) -> NSImage {
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
        }

        let laid: [(line: CTLine, ink: CGRect)] = pieces.filter { !$0.text.isEmpty }.map { piece in
            let attributed = NSAttributedString(string: piece.text,
                                                attributes: [.font: piece.font, .foregroundColor: color])
            let line = CTLineCreateWithAttributedString(attributed)
            return (line, inkBounds(line))
        }
        guard !laid.isEmpty else { return NSImage(size: NSSize(width: 1, height: 1)) }

        let pad = max(0, padding)
        let height = NSStatusBar.system.thickness
        let inkWidth = laid.reduce(0.0) { $0 + $1.ink.width } + gap * Double(laid.count - 1)

        let image = NSImage(size: NSSize(width: ceil(inkWidth + pad * 2), height: height))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            var x = pad
            for piece in laid {
                context.textPosition = CGPoint(
                    x: x - piece.ink.minX,
                    y: (height - piece.ink.height) / 2 - piece.ink.minY + verticalOffset)
                CTLineDraw(piece.line, context)
                x += piece.ink.width + gap
            }
        }
        image.unlockFocus()
        image.isTemplate = false   // keep colour emoji in colour
        return image
    }
}
