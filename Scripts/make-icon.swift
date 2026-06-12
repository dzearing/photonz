// Generates Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
// Draws a macOS-style squircle with a violet glass gradient and a camera
// aperture glyph. Regenerate only when intentionally changing the icon.
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: artwork occupies ~80% of the canvas.
    let inset = size * 0.10
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Background gradient: deep indigo to vivid violet.
    NSGraphicsContext.current!.saveGraphicsState()
    squircle.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.85, alpha: 1),
        NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.95, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: 60)

    // Soft top-edge sheen for the glass feel.
    let sheen = NSGradient(starting: NSColor(white: 1, alpha: 0.35), ending: NSColor(white: 1, alpha: 0))!
    sheen.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.current!.restoreGraphicsState()

    // Aperture: 6 blades around a center circle.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = rect.width * 0.30
    let lineWidth = rect.width * 0.045
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3
        let start = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
        let endAngle = angle + .pi / 3 * 1.55
        let end = CGPoint(x: center.x + cos(endAngle) * outer * 0.42, y: center.y + sin(endAngle) * outer * 0.42)
        ctx.move(to: start)
        ctx.addLine(to: end)
    }
    ctx.strokePath()
    ctx.setLineWidth(lineWidth * 0.9)
    ctx.strokeEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    writePNG(drawIcon(size: 1024), to: iconset.appendingPathComponent("\(name).png"), pixels: px)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "Resources/AppIcon.iconset", "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
