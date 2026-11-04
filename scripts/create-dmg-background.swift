import AppKit

let outputPath = CommandLine.arguments[1]
let logicalSize = NSSize(width: 980, height: 680)
let scale = 2
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(logicalSize.width) * scale,
    pixelsHigh: Int(logicalSize.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = logicalSize

let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

let bounds = NSRect(origin: .zero, size: logicalSize)
NSGradient(colors: [color(0x111A2A), color(0x0A0F1B)])!.draw(in: bounds, angle: 90)

drawCentered("DROPSHAKE", at: NSPoint(x: 490, y: 590), font: .systemFont(ofSize: 29, weight: .bold), color: .white)
drawCentered("Move files with a shake", at: NSPoint(x: 490, y: 555), font: .systemFont(ofSize: 16, weight: .medium), color: color(0xAEB9D0))

let leftTile = NSBezierPath(roundedRect: NSRect(x: 128, y: 264, width: 236, height: 222), xRadius: 28, yRadius: 28)
color(0xFFFFFF, alpha: 0.035).setFill()
leftTile.fill()
color(0xFFFFFF, alpha: 0.08).setStroke()
leftTile.lineWidth = 1
leftTile.stroke()

let rightTile = NSBezierPath(roundedRect: NSRect(x: 616, y: 264, width: 236, height: 222), xRadius: 28, yRadius: 28)
color(0xFFFFFF, alpha: 0.035).setFill()
rightTile.fill()
color(0xFFFFFF, alpha: 0.08).setStroke()
rightTile.lineWidth = 1
rightTile.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 397, y: 377))
arrow.line(to: NSPoint(x: 583, y: 377))
arrow.move(to: NSPoint(x: 551, y: 405))
arrow.line(to: NSPoint(x: 583, y: 377))
arrow.line(to: NSPoint(x: 551, y: 349))
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0x8DA8FF).setStroke()
arrow.stroke()

drawCentered("Drag Dropshake to Applications to install", at: NSPoint(x: 490, y: 126), font: .systemFont(ofSize: 17, weight: .semibold), color: .white)
drawCentered("Your files stay on your Mac", at: NSPoint(x: 490, y: 94), font: .systemFont(ofSize: 13, weight: .regular), color: color(0xAEB9D0))

NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: outputPath))

func drawCentered(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: font.pointSize > 20 ? 2.0 : 0.2
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}
