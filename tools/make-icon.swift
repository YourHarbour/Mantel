// Draws AppIcon.icns from scratch. Run via tools/make-icon.sh.
import AppKit

// MARK: - Geometry helpers

/// Apple's app icon shape is close to a superellipse; a plain rounded rect looks visibly "rounder".
func superellipse(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// MARK: - Icon

func drawIcon(size S: CGFloat, into context: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS app icons leave ~10% of the canvas empty around the rounded square.
    let inset = S * 100 / 1024
    let box = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let shape = superellipse(in: box)

    // Drop shadow under the whole tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03,
                      color: rgb(0, 0, 0, 0.28))
    context.addPath(shape)
    context.setFillColor(rgb(30, 47, 122))
    context.fillPath()
    context.restoreGState()

    // Background gradient.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [rgb(88, 122, 255), rgb(46, 62, 168), rgb(24, 32, 96)] as CFArray,
                                locations: [0, 0.55, 1])!
    context.drawLinearGradient(background,
                               start: CGPoint(x: box.midX, y: box.maxY),
                               end: CGPoint(x: box.midX, y: box.minY),
                               options: [])
    // Soft highlight along the top edge.
    let highlight = CGGradient(colorsSpace: space,
                               colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray,
                               locations: [0, 1])!
    context.drawLinearGradient(highlight,
                               start: CGPoint(x: box.midX, y: box.maxY),
                               end: CGPoint(x: box.midX, y: box.maxY - box.height * 0.45),
                               options: [])
    context.restoreGState()

    // A mantelpiece: one horizontal slab with things arranged along it. That is the whole
    // app in one picture — the menu bar is the shelf, the icons are what sits on it — and it
    // gives the name something to point at.
    func px(_ u: CGFloat) -> CGFloat { box.minX + box.width * u }
    func py(_ v: CGFloat) -> CGFloat { box.minY + box.height * v }

    let shelfTop = py(0.435)
    let shelfHeight = box.height * 0.075
    let shelf = CGRect(x: px(0.135), y: shelfTop - shelfHeight,
                       width: box.width * 0.73, height: shelfHeight)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -S * 0.014), blur: S * 0.03,
                      color: rgb(8, 16, 60, 0.5))

    let radius = shelfHeight * 0.32
    context.addPath(CGPath(roundedRect: shelf, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(rgb(240, 244, 255))
    context.fillPath()

    // Three ornaments standing on the slab. Different heights so the silhouette still reads
    // at 16pt, where the shapes themselves are only a couple of pixels wide.
    let objectWidth = box.width * 0.135
    let tall = CGRect(x: px(0.215), y: shelfTop, width: objectWidth, height: box.height * 0.235)
    let short = CGRect(x: px(0.650), y: shelfTop, width: objectWidth, height: box.height * 0.155)
    let ballRadius = box.width * 0.077
    let ball = CGRect(x: px(0.5) - ballRadius, y: shelfTop, width: ballRadius * 2, height: ballRadius * 2)

    let objectRadius = objectWidth * 0.3
    context.addPath(CGPath(roundedRect: tall, cornerWidth: objectRadius, cornerHeight: objectRadius,
                           transform: nil))
    context.setFillColor(rgb(255, 255, 255))
    context.fillPath()

    context.addEllipse(in: ball)
    context.setFillColor(rgb(255, 176, 92))
    context.fillPath()

    context.addPath(CGPath(roundedRect: short, cornerWidth: objectRadius, cornerHeight: objectRadius,
                           transform: nil))
    context.setFillColor(rgb(255, 96, 104))
    context.fillPath()
    context.restoreGState()

    // Hairline rim so the tile keeps an edge on a white background.
    context.addPath(shape)
    context.setStrokeColor(rgb(255, 255, 255, 0.16))
    context.setLineWidth(max(1, S * 0.0035))
    context.strokePath()
}

func render(size: Int) -> Data {
    let S = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(size: S, into: context)
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Output

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    try! render(size: size).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(variants.count) sizes to \(out)")
