#!/usr/bin/env swift
// Renders the Gap mode specimen set into Tests/PhotonzRenderTests/Fixtures:
// stacked text lines (a display heading and body copy), stacked cards, side by
// side buttons, an icon beside a label, a row of chips and text over a divider,
// each at 1x and 2x, plus `gap-specimens.json` naming every element's box in
// image pixels. Shapes are boxed where they were drawn; a line of text is boxed
// by scanning its own pixels, the way a person lays a caliper across the ink.
//
//     swift Scripts/make-gap-specimens.swift
//
// Only when the specimens themselves change: the tests pin numbers against the
// committed pictures.
import AppKit
import CoreText
import Foundation

let out = URL(fileURLWithPath: "Tests/PhotonzRenderTests/Fixtures")

struct RGB { var r, g, b: CGFloat }
func hex(_ v: UInt32) -> RGB {
    RGB(r: CGFloat((v >> 16) & 0xFF) / 255, g: CGFloat((v >> 8) & 0xFF) / 255, b: CGFloat(v & 0xFF) / 255)
}

/// One element to draw, in POINTS, top-left origin.
enum Item {
    case text(String, String, x: CGFloat, baseline: CGFloat, size: CGFloat, weight: NSFont.Weight, color: RGB)
    case box(String, CGRect, fill: RGB, border: RGB?, radius: CGFloat)
    case disc(String, CGRect, fill: RGB)
    case rule(String, CGRect, fill: RGB)
}

struct Specimen {
    var name: String
    var size: CGSize
    var background: RGB
    var items: [Item]
}

let light = hex(0xF2F2F7), white = hex(0xFFFFFF), ink = hex(0x1C1C1E), hairline = hex(0xC6C6C8)
let specimens: [Specimen] = [
    Specimen(name: "gap-heading-lines", size: CGSize(width: 420, height: 200), background: hex(0x0A0A12), items: [
        .text("upper", "Screenshots", x: 20, baseline: 70, size: 56, weight: .bold, color: hex(0xF5F5F7)),
        .text("lower", "recordings", x: 60, baseline: 150, size: 56, weight: .bold, color: hex(0xF5F5F7)),
    ]),
    Specimen(name: "gap-body-lines", size: CGSize(width: 320, height: 110), background: white, items: [
        .text("line1", "The quick brown fox jumps over", x: 16, baseline: 30, size: 13, weight: .regular, color: ink),
        .text("line2", "a lazy dog, typing quietly", x: 16, baseline: 52, size: 13, weight: .regular, color: ink),
        .text("line3", "Settings and privacy", x: 16, baseline: 74, size: 13, weight: .regular, color: ink),
    ]),
    Specimen(name: "gap-cards", size: CGSize(width: 340, height: 220), background: light, items: [
        .box("cardA", CGRect(x: 20, y: 20, width: 300, height: 80), fill: white, border: hex(0xD1D1D6), radius: 10),
        .box("cardB", CGRect(x: 20, y: 112, width: 300, height: 80), fill: white, border: hex(0xD1D1D6), radius: 10),
        .text("titleA", "Notifications", x: 36, baseline: 46, size: 15, weight: .semibold, color: ink),
        .text("bodyA", "Banners, sounds and badges", x: 36, baseline: 72, size: 13, weight: .regular, color: hex(0x6E6E73)),
    ]),
    Specimen(name: "gap-buttons", size: CGSize(width: 280, height: 90), background: white, items: [
        .box("cancel", CGRect(x: 30, y: 30, width: 100, height: 30), fill: hex(0xE5E5EA), border: nil, radius: 7),
        .box("save", CGRect(x: 142, y: 30, width: 100, height: 30), fill: hex(0x0A84FF), border: nil, radius: 7),
        .text("cancelLabel", "Cancel", x: 57, baseline: 50, size: 13, weight: .medium, color: ink),
        .text("saveLabel", "Save", x: 177, baseline: 50, size: 13, weight: .medium, color: white),
    ]),
    Specimen(name: "gap-icon-label", size: CGSize(width: 220, height: 70), background: white, items: [
        .disc("icon", CGRect(x: 24, y: 24, width: 22, height: 22), fill: hex(0x0A84FF)),
        .text("label", "Downloads", x: 56, baseline: 40, size: 15, weight: .regular, color: ink),
    ]),
    Specimen(name: "gap-chips", size: CGSize(width: 330, height: 70), background: white, items: [
        .box("chip1", CGRect(x: 16, y: 20, width: 70, height: 28), fill: hex(0xF2F2F7), border: hex(0xD1D1D6), radius: 14),
        .box("chip2", CGRect(x: 94, y: 20, width: 64, height: 28), fill: hex(0xF2F2F7), border: hex(0xD1D1D6), radius: 14),
        .box("chip3", CGRect(x: 166, y: 20, width: 76, height: 28), fill: hex(0xF2F2F7), border: hex(0xD1D1D6), radius: 14),
        .box("chip4", CGRect(x: 250, y: 20, width: 64, height: 28), fill: hex(0xF2F2F7), border: hex(0xD1D1D6), radius: 14),
        .text("chip1Label", "Design", x: 30, baseline: 38, size: 13, weight: .regular, color: ink),
        .text("chip2Label", "Video", x: 109, baseline: 38, size: 13, weight: .regular, color: ink),
        .text("chip3Label", "Capture", x: 180, baseline: 38, size: 13, weight: .regular, color: ink),
        .text("chip4Label", "Audio", x: 265, baseline: 38, size: 13, weight: .regular, color: ink),
    ]),
    Specimen(name: "gap-divider", size: CGSize(width: 300, height: 100), background: white, items: [
        .text("above", "General settings", x: 20, baseline: 32, size: 15, weight: .semibold, color: ink),
        .rule("divider", CGRect(x: 20, y: 44, width: 260, height: 1), fill: hairline),
        .text("below", "Appearance and layout", x: 20, baseline: 68, size: 13, weight: .regular, color: ink),
    ]),
]

func render(_ specimen: Specimen, scale: CGFloat) throws -> [String: [Int]] {
    let w = Int(specimen.size.width * scale), h = Int(specimen.size.height * scale)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func set(_ c: RGB) { ctx.setFillColor(CGColor(colorSpace: space, components: [c.r, c.g, c.b, 1])!) }
    // Top-left origin in points.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    set(specimen.background)
    ctx.fill(CGRect(origin: .zero, size: specimen.size))
    var boxes: [String: [Int]] = [:]
    func px(_ r: CGRect) -> [Int] {
        [Int((r.minX * scale).rounded()), Int((r.minY * scale).rounded()),
         Int((r.width * scale).rounded()), Int((r.height * scale).rounded())]
    }
    var texts: [(String, CGRect)] = []
    for item in specimen.items {
        switch item {
        case let .box(name, rect, fill, border, radius):
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if let border {
                set(border)
                ctx.addPath(path); ctx.fillPath()
                set(fill)
                let inner = rect.insetBy(dx: 1, dy: 1)
                ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
                ctx.fillPath()
            } else {
                set(fill)
                ctx.addPath(path); ctx.fillPath()
            }
            boxes[name] = px(rect)
        case let .disc(name, rect, fill):
            set(fill)
            ctx.fillEllipse(in: rect)
            boxes[name] = px(rect)
        case let .rule(name, rect, fill):
            set(fill)
            ctx.fill(rect)
            boxes[name] = px(rect)
        case let .text(name, string, x, baseline, size, weight, color):
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let attributed = NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.saveGState()
            ctx.translateBy(x: x, y: baseline)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            texts.append((name, CGRect(x: x - 2, y: baseline - ascent - 2,
                                       width: CGFloat(width) + 4, height: ascent + descent + 4)))
        }
    }
    let image = ctx.makeImage()!
    // Ink boxes, read off the pixels: anything that differs from what sits
    // around the line (the page, or the button it is printed on).
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    func luma(_ x: Int, _ y: Int) -> Int {
        let i = (y * w + x) * 4
        return (299 * Int(data[i]) + 587 * Int(data[i + 1]) + 114 * Int(data[i + 2])) / 1000
    }
    for (name, region) in texts {
        let x0 = max(0, Int(region.minX * scale)), x1 = min(w - 1, Int(region.maxX * scale))
        // Bitmap rows run top-down here because of the flip above.
        let y0 = max(0, Int(region.minY * scale)), y1 = min(h - 1, Int(region.maxY * scale))
        var hist = [Int: Int]()
        for y in y0...y1 { for x in x0...x1 { hist[luma(x, y), default: 0] += 1 } }
        let back = hist.max { $0.value < $1.value }!.key
        var top = Int.max, bottom = -1, left = Int.max, right = -1
        for y in y0...y1 {
            for x in x0...x1 where abs(luma(x, y) - back) >= 24 {
                top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
            }
        }
        boxes[name] = [left, top, right - left + 1, bottom - top + 1]
    }
    let file = out.appendingPathComponent("\(specimen.name)-\(Int(scale))x.png")
    let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 72 * scale,
                                             kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return boxes
}

var manifest: [String: [String: [Int]]] = [:]
for specimen in specimens {
    for scale in [1, 2] as [CGFloat] {
        manifest["\(specimen.name)-\(Int(scale))x"] = try render(specimen, scale: scale)
    }
}
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("gap-specimens.json"))
print("wrote \(manifest.count) specimens")
