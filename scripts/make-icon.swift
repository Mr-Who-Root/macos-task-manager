// Renders the app icon (a pulse line on a blue tile) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // macOS icon grid: an 824/1024 tile centred on the canvas, with a soft shadow.
    let inset = s * 100 / 1024
    let tile = NSRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.27, green: 0.84, blue: 0.86, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.55, blue: 0.93, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.33, blue: 0.80, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -55)

    // Faint graph grid.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSColor.white.withAlphaComponent(0.13).setStroke()
    let grid = NSBezierPath()
    grid.lineWidth = max(1, s / 256)
    for i in 1..<6 {
        let y = tile.minY + tile.height * CGFloat(i) / 6
        grid.move(to: NSPoint(x: tile.minX, y: y))
        grid.line(to: NSPoint(x: tile.maxX, y: y))
        let x = tile.minX + tile.width * CGFloat(i) / 6
        grid.move(to: NSPoint(x: x, y: tile.minY))
        grid.line(to: NSPoint(x: x, y: tile.maxY))
    }
    grid.stroke()

    // Pulse line with a translucent fill below it.
    let points: [(CGFloat, CGFloat)] = [(0.0, 0.42), (0.22, 0.42), (0.34, 0.72), (0.49, 0.22), (0.62, 0.52), (0.76, 0.46), (1.0, 0.46)]
    let line = NSBezierPath()
    for (i, p) in points.enumerated() {
        let point = NSPoint(x: tile.minX + tile.width * p.0, y: tile.minY + tile.height * p.1)
        i == 0 ? line.move(to: point) : line.line(to: point)
    }
    let fill = line.copy() as! NSBezierPath
    fill.line(to: NSPoint(x: tile.maxX, y: tile.minY))
    fill.line(to: NSPoint(x: tile.minX, y: tile.minY))
    fill.close()
    NSColor.white.withAlphaComponent(0.18).setFill()
    fill.fill()
    NSColor.white.setStroke()
    line.lineWidth = s * 0.045
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = render(size: base * scale) {
            try data.write(to: URL(fileURLWithPath: "\(output)/\(name)"))
        }
    }
}
