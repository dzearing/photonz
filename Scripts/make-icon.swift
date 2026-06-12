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

    // Baked drop shadow, like every stock macOS icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.45, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Background gradient: deep indigo to vivid violet.
    NSGraphicsContext.current!.saveGraphicsState()
    squircle.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.42, green: 0.18, blue: 0.83, alpha: 1),
        NSColor(calibratedRed: 0.72, green: 0.34, blue: 0.95, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: 60)

    // Restrained top sheen for the glass feel — strong enough to read as a
    // surface, weak enough that the violet still carries the icon.
    let sheen = NSGradient(starting: NSColor(white: 1, alpha: 0.18), ending: NSColor(white: 1, alpha: 0))!
    sheen.draw(in: CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.38,
                          width: rect.width, height: rect.height * 0.38), angle: -90)

    // Glass edge: hairline inner highlight so the rim catches light.
    let edge = rect.insetBy(dx: size * 0.004, dy: size * 0.004)
    let edgePath = NSBezierPath(roundedRect: edge, xRadius: radius - size * 0.004,
                                yRadius: radius - size * 0.004)
    edgePath.lineWidth = size * 0.008
    NSColor(white: 1, alpha: 0.28).setStroke()
    edgePath.stroke()

    NSGraphicsContext.current!.restoreGraphicsState()

    // Aperture: 6 blades clipped inside the ring so nothing pokes out.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = rect.width * 0.30
    let lineWidth = rect.width * 0.045
    ctx.saveGState()
    // Soft shadow under the glyph lifts it off the glass.
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineWidth * 0.9)
    ctx.strokeEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
    // Blades draw inside the ring only.
    ctx.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
        .insetBy(dx: lineWidth * 0.30, dy: lineWidth * 0.30))
    ctx.clip()
    ctx.setLineWidth(lineWidth)
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3
        let start = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
        let endAngle = angle + .pi / 3 * 1.55
        let end = CGPoint(x: center.x + cos(endAngle) * outer * 0.42, y: center.y + sin(endAngle) * outer * 0.42)
        ctx.move(to: start)
        ctx.addLine(to: end)
    }
    ctx.strokePath()
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
