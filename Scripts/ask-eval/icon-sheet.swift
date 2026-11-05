#!/usr/bin/env swift
// The sheet an icon case is judged on (README, "Icon cases"): the icon large,
// the same icon at 64, 24 and 16 pixels on light and on dark, and a reference
// row of how SF Symbols, Lucide and Material Symbols draw a comparable icon.
// The references are drawn here from the Mac's own symbols and from SVG files
// fetched for the eval: they are only ever shown to the judge, never to Ask.
//
//   swift Scripts/ask-eval/icon-sheet.swift <out.png> <icon.png> <sf symbol or -> [<reference.svg> <label>]...
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: icon-sheet.swift <out.png> <icon.png> <sf symbol or -> [<svg> <label>]...\n".data(using: .utf8)!)
    exit(2)
}
let size = NSSize(width: 980, height: 700)
let scale: CGFloat = 1
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor(white: 0.93, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func label(_ words: String, at point: NSPoint, size: CGFloat = 13, bold: Bool = false) {
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: NSColor(white: 0.25, alpha: 1)]).draw(at: point)
}
/// Drawn at this many pixels from the full picture: a real small size, shown
/// with its pixels kept so the judge sees what 16 pixels really leaves.
func small(_ image: NSImage, pixels: Int) -> NSImage {
    let out = NSImage(size: NSSize(width: pixels, height: pixels))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    out.unlockFocus()
    return out
}

/// Whether the picture is a dark glyph with nothing behind it: on the dark row
/// it is then shown in light ink, the way the app's own dark preview chip shows
/// one (`IconPreviews.inkOnDarkHex`), rather than black on black.
func isDarkGlyph(_ image: NSImage) -> Bool {
    guard let data = small(image, pixels: 64).tiffRepresentation, let bits = NSBitmapImageRep(data: data) else { return false }
    var inked = 0, clear = 0, dark = 0
    for y in 0..<bits.pixelsHigh {
        for x in 0..<bits.pixelsWide {
            guard let colour = bits.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if colour.alphaComponent < 0.5 { clear += 1; continue }
            inked += 1
            if colour.brightnessComponent < 0.35 { dark += 1 }
        }
    }
    return clear > 0 && inked > 0 && Double(dark) / Double(inked) > 0.8
}
func lightened(_ image: NSImage) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSColor(calibratedRed: 0.95, green: 0.96, blue: 1, alpha: 1).setFill()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}
let glyph = isDarkGlyph(icon)

let big: CGFloat = 420
let top = size.height - 24
label("THE WORK", at: NSPoint(x: 24, y: top - 16), bold: true)
let bigBox = NSRect(x: 24, y: top - 24 - big, width: big, height: big)
NSColor.white.setFill(); bigBox.fill()
// The picture keeps its proportions: a wide canvas is shown wide.
let fit = min(big / max(icon.size.width, 1), big / max(icon.size.height, 1))
let drawn = NSSize(width: icon.size.width * fit, height: icon.size.height * fit)
icon.draw(in: NSRect(x: bigBox.midX - drawn.width / 2, y: bigBox.midY - drawn.height / 2, width: drawn.width, height: drawn.height))

var x = bigBox.maxX + 32
for pixels in [64, 24, 16] {
    let picture = small(icon, pixels: pixels)
    let shown = CGFloat(pixels) * 2
    for (row, ground) in [NSColor.white, NSColor(white: 0.07, alpha: 1)].enumerated() {
        let y = bigBox.maxY - 170 - CGFloat(row) * 170
        let tile = NSRect(x: x, y: y, width: 150, height: 150)
        ground.setFill(); tile.fill()
        context.imageInterpolation = .none
        (row == 1 && glyph ? lightened(picture) : picture)
            .draw(in: NSRect(x: tile.midX - shown / 2, y: tile.midY - shown / 2, width: shown, height: shown))
        context.imageInterpolation = .high
    }
    label("\(pixels) px (shown 2x)", at: NSPoint(x: x, y: bigBox.maxY - 340 - 24), size: 12)
    x += 164
}

label("REFERENCE: how others draw a comparable icon (not the work)", at: NSPoint(x: 24, y: 192), bold: true)
var tiles: [(NSImage, String)] = []
if args[2] != "-", let symbol = NSImage(systemSymbolName: args[2], accessibilityDescription: nil) {
    let sized = symbol.withSymbolConfiguration(.init(pointSize: 96, weight: .regular)) ?? symbol
    tiles.append((sized, "SF Symbols"))
}
var index = 3
while index + 1 < args.count {
    if let image = NSImage(contentsOfFile: args[index]) { tiles.append((image, args[index + 1])) }
    index += 2
}
x = 24
for (image, name) in tiles {
    let tile = NSRect(x: x, y: 40, width: 140, height: 140)
    NSColor.white.setFill(); tile.fill()
    let side: CGFloat = 96
    let ratio = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
    let shown = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
    image.draw(in: NSRect(x: tile.midX - shown.width / 2, y: tile.midY - shown.height / 2, width: shown.width, height: shown.height))
    label(name, at: NSPoint(x: x, y: 18), size: 12)
    x += 156
}
NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[0]))
