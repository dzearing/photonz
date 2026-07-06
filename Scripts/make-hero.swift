#!/usr/bin/env swift
// Renders the website hero: a Photonz document mid-redline — a clean app-UI
// mock annotated with the tools the app actually ships (dimension measures,
// a zoom callout, an arrow note, a highlight, a marching-ants selection).
// Drawn with CoreGraphics/AppKit in the same visual styles as the app's
// rasterizers. Output: site/assets/hero.png, 2400×1500 (@2x for ~1200×750).
//
//   swift Scripts/make-hero.swift
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let W: CGFloat = 2400, H: CGFloat = 1500

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: Int(W), height: Int(H),
                          bitsPerComponent: 8, bytesPerRow: Int(W) * 4,
                          space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Top-left coordinate helpers (the design reads top-down).
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: H - y - h, width: w, height: h)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: H - y) }

func fill(_ rect: CGRect, _ color: CGColor, radius: CGFloat = 0) {
    ctx.saveGState()
    let path = radius > 0 ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                          : CGPath(rect: rect, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}
func stroke(_ rect: CGRect, _ color: CGColor, width: CGFloat, radius: CGFloat = 0, dash: [CGFloat] = []) {
    ctx.saveGState()
    let path = radius > 0 ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                          : CGPath(rect: rect, transform: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
    ctx.strokePath()
    ctx.restoreGState()
}
func line(_ a: CGPoint, _ b: CGPoint, _ color: CGColor, width: CGFloat, dash: [CGFloat] = []) {
    ctx.saveGState()
    ctx.move(to: a); ctx.addLine(to: b)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
    ctx.strokePath()
    ctx.restoreGState()
}
func shadow(_ enabled: Bool, blur: CGFloat = 40, dy: CGFloat = -16, alpha: CGFloat = 0.18) {
    if enabled { ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur,
                               color: CGColor(gray: 0.1, alpha: alpha)) }
    else { ctx.setShadow(offset: .zero, blur: 0, color: nil) }
}
@discardableResult
func text(_ string: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, mono: Bool = false, centeredAt: Bool = false) -> CGSize {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: string, attributes: attrs)
    let bounds = str.size()
    let origin = centeredAt ? CGPoint(x: p.x - bounds.width / 2, y: p.y - bounds.height / 2) : p
    str.draw(at: origin)
    return bounds
}

// MARK: - Palette
let paper = CGColor(srgbRed: 0.953, green: 0.953, blue: 0.965, alpha: 1)  // #F3F3F6
let white = CGColor(gray: 1, alpha: 1)
let hairline = CGColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1)
let inkFaint = CGColor(srgbRed: 0.90, green: 0.90, blue: 0.93, alpha: 1)
let inkSoft = CGColor(srgbRed: 0.80, green: 0.80, blue: 0.85, alpha: 1)
let violet = CGColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1) // #8B5CF6
let violetSoft = CGColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 0.14)
let red = CGColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1)      // #FF3B30
let yellow = CGColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 0.38)
let slate = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.30, alpha: 1)
let slateSoft = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.62, alpha: 1)

// MARK: - The app-UI mock being redlined
fill(CGRect(x: 0, y: 0, width: W, height: H), paper)

// Sidebar
let sidebarW: CGFloat = 420
fill(R(0, 0, sidebarW, H), white)
line(P(sidebarW, 0), P(sidebarW, H), hairline, width: 2)
fill(R(48, 56, 56, 56), violet, radius: 16)                       // logo mark
text("Prism", at: P(128, 100), size: 40, weight: .bold, color: slate)
let navItems = ["Overview", "Reports", "Segments", "Events", "Settings"]
for (i, item) in navItems.enumerated() {
    let y = 200 + CGFloat(i) * 96
    if i == 0 {
        fill(R(32, y - 18, sidebarW - 64, 72), violetSoft, radius: 18)
        text(item, at: P(72, y + 30), size: 32, weight: .semibold,
             color: NSColor(srgbRed: 0.42, green: 0.27, blue: 0.80, alpha: 1))
    } else {
        text(item, at: P(72, y + 30), size: 32, weight: .medium, color: slateSoft)
    }
}

// Header
let headerH: CGFloat = 132
fill(R(sidebarW, 0, W - sidebarW, headerH), white)
line(P(sidebarW, headerH), P(W, headerH), hairline, width: 2)
text("Analytics Overview", at: P(sidebarW + 56, 84), size: 42, weight: .bold, color: slate)
// Header buttons
let shareRect = R(W - 470, 34, 180, 64)
fill(shareRect, inkFaint, radius: 32)
text("Share", at: CGPoint(x: shareRect.midX, y: shareRect.midY), size: 30,
     weight: .semibold, color: slateSoft, centeredAt: true)
let exportRect = R(W - 260, 34, 200, 64)
fill(exportRect, violet, radius: 32)
text("Export", at: CGPoint(x: exportRect.midX, y: exportRect.midY), size: 30,
     weight: .semibold, color: .white, centeredAt: true)

// Stat cards
let contentX = sidebarW + 56
let cardY: CGFloat = 196
let cardW: CGFloat = 560, cardH: CGFloat = 240, gap: CGFloat = 48
let stats: [(String, String, String)] = [("Sessions", "48,210", "+12.4%"),
                                         ("Conversion", "3.86%", "+0.9%"),
                                         ("Revenue", "$92.4k", "+18.2%")]
var cardRects: [CGRect] = []
for (i, stat) in stats.enumerated() {
    let x = contentX + CGFloat(i) * (cardW + gap)
    let rect = R(x, cardY, cardW, cardH)
    cardRects.append(rect)
    ctx.saveGState(); shadow(true, blur: 30, dy: -10, alpha: 0.08)
    fill(rect, white, radius: 24)
    ctx.restoreGState()
    text(stat.0, at: P(x + 40, cardY + 66), size: 28, weight: .medium, color: slateSoft)
    text(stat.1, at: P(x + 40, cardY + 140), size: 52, weight: .bold, color: slate)
    text(stat.2, at: P(x + 40, cardY + 196), size: 26, weight: .semibold,
         color: NSColor(srgbRed: 0.20, green: 0.66, blue: 0.36, alpha: 1))
}

// Chart card
let chartY = cardY + cardH + 56
let chartW = cardW * 2 + gap
let chartH: CGFloat = 560
let chartRect = R(contentX, chartY, chartW, chartH)
ctx.saveGState(); shadow(true, blur: 30, dy: -10, alpha: 0.08)
fill(chartRect, white, radius: 24)
ctx.restoreGState()
text("Weekly active users", at: P(contentX + 40, chartY + 70), size: 32, weight: .semibold, color: slate)
// grid lines + smooth series
for i in 0..<4 {
    let gy = chartY + 140 + CGFloat(i) * 110
    line(P(contentX + 40, gy), P(contentX + chartW - 40, gy), inkFaint, width: 2)
}
let seriesY: [CGFloat] = [430, 380, 402, 330, 352, 268, 300, 236, 210]
let px0 = contentX + 60, px1 = contentX + chartW - 60
let series = CGMutablePath()
for (i, sy) in seriesY.enumerated() {
    let t = CGFloat(i) / CGFloat(seriesY.count - 1)
    let p = P(px0 + (px1 - px0) * t, chartY + sy)
    if i == 0 { series.move(to: p) } else {
        let prevT = CGFloat(i - 1) / CGFloat(seriesY.count - 1)
        let prev = P(px0 + (px1 - px0) * prevT, chartY + seriesY[i - 1])
        let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
        series.addQuadCurve(to: mid, control: CGPoint(x: (prev.x + mid.x) / 2, y: prev.y))
        series.addQuadCurve(to: p, control: CGPoint(x: (mid.x + p.x) / 2, y: p.y))
    }
}
// area fill under the line
ctx.saveGState()
let area = series.mutableCopy()!
area.addLine(to: P(px1, chartY + chartH - 60))
area.addLine(to: P(px0, chartY + chartH - 60))
area.closeSubpath()
ctx.addPath(area)
ctx.clip()
let grad = CGGradient(colorsSpace: space,
                      colors: [CGColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 0.30),
                               CGColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: P(px0, chartY + 200), end: P(px0, chartY + chartH - 60), options: [])
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(series)
ctx.setStrokeColor(violet)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()

// Table card
let tableX = contentX + chartW + gap
let tableRect = R(tableX, chartY, cardW, chartH)
ctx.saveGState(); shadow(true, blur: 30, dy: -10, alpha: 0.08)
fill(tableRect, white, radius: 24)
ctx.restoreGState()
text("Top pages", at: P(tableX + 40, chartY + 70), size: 32, weight: .semibold, color: slate)
let rows = ["/pricing", "/docs/start", "/blog/launch", "/changelog", "/integrations"]
for (i, row) in rows.enumerated() {
    let ry = chartY + 130 + CGFloat(i) * 84
    if i == 2 { fill(R(tableX + 24, ry - 14, cardW - 48, 64), yellow, radius: 10) } // Photonz highlight
    text(row, at: P(tableX + 48, ry + 32), size: 28, weight: .medium, color: slate, mono: true)
    fill(R(tableX + cardW - 160, ry, 112, 36), inkFaint, radius: 18)
}

// MARK: - Photonz artifacts on top

// 1) Dimension measures (red, bracket form, mono labels in white pills)
func measurePill(_ label: String, at center: CGPoint) {
    let font = NSFont.monospacedSystemFont(ofSize: 27, weight: .semibold)
    let str = NSAttributedString(string: label, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: red)!])
    let size = str.size()
    let pill = CGRect(x: center.x - size.width / 2 - 16, y: center.y - size.height / 2 - 7,
                      width: size.width + 32, height: size.height + 14)
    ctx.saveGState(); shadow(true, blur: 12, dy: -4, alpha: 0.18)
    fill(pill, white, radius: pill.height / 2)
    ctx.restoreGState()
    stroke(pill, CGColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 0.35), width: 2, radius: pill.height / 2)
    str.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
}
func hMeasure(fromX: CGFloat, toX: CGFloat, y: CGFloat, label: String) {
    let a = P(fromX, y), b = P(toX, y)
    line(a, b, red, width: 3)
    line(P(fromX, y - 14), P(fromX, y + 14), red, width: 3)
    line(P(toX, y - 14), P(toX, y + 14), red, width: 3)
    measurePill(label, at: CGPoint(x: (a.x + b.x) / 2, y: a.y + 34))
}
func vMeasure(x: CGFloat, fromY: CGFloat, toY: CGFloat, label: String) {
    line(P(x, fromY), P(x, toY), red, width: 3)
    line(P(x - 14, fromY), P(x + 14, fromY), red, width: 3)
    line(P(x - 14, toY), P(x + 14, toY), red, width: 3)
    measurePill(label, at: CGPoint(x: P(x, 0).x + 78, y: P(0, (fromY + toY) / 2).y))
}
// gap between card 1 and card 2, and sidebar→content inset
hMeasure(fromX: contentX + cardW, toX: contentX + cardW + gap, y: cardY + cardH / 2, label: "24")
vMeasure(x: sidebarW + 28, fromY: headerH, toY: cardY, label: "32")

// 2) Marching-ants selection around stat card 3 (region selection)
let antsRect = cardRects[2].insetBy(dx: -14, dy: -14)
stroke(antsRect, white, width: 3)
stroke(antsRect, CGColor(gray: 0.05, alpha: 1), width: 3, dash: [14, 14])

// 3) Red arrow + note pointing into the chart dip
let arrowTip = P(px0 + (px1 - px0) * 0.58, chartY + 305)
let arrowTail = P(px0 + (px1 - px0) * 0.58 + 220, chartY + 130)
ctx.saveGState()
ctx.setStrokeColor(red)
ctx.setFillColor(red)
ctx.setLineWidth(9)
ctx.setLineCap(.round)
// slight curve for a hand-placed feel
ctx.move(to: arrowTail)
ctx.addQuadCurve(to: CGPoint(x: arrowTip.x + 40, y: arrowTip.y + 44),
                 control: CGPoint(x: arrowTail.x - 150, y: arrowTail.y - 10))
ctx.strokePath()
// arrowhead
let angle = atan2((arrowTip.y + 44) - arrowTip.y - 88, 40 - 0 - 80) // aim down-left
let tipDir = CGPoint(x: cos(angle), y: sin(angle))
_ = tipDir
let head = CGMutablePath()
head.move(to: arrowTip)
head.addLine(to: CGPoint(x: arrowTip.x + 58, y: arrowTip.y + 20))
head.addLine(to: CGPoint(x: arrowTip.x + 22, y: arrowTip.y + 58))
head.closeSubpath()
ctx.addPath(head)
ctx.fillPath()
ctx.restoreGState()
// note text with contrast shadow (like the app's text tool)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 10, color: CGColor(gray: 1, alpha: 0.9))
text("drop-off after v2.3 ship", at: CGPoint(x: arrowTail.x - 120, y: arrowTail.y + 14),
     size: 34, weight: .bold, color: NSColor(cgColor: red)!)
ctx.restoreGState()

// 4) Zoom callout magnifying the Export button (signature feature)
let srcCenter = CGPoint(x: exportRect.midX, y: exportRect.midY)
let srcR: CGFloat = 64
let calloutCenter = P(W - 380, 820)
let calloutR: CGFloat = 200
// leader lines (tangent-ish pair)
for offset in [CGFloat(-0.35), 0.35] {
    let sx = srcCenter.x + cos(offset + .pi / 2) * srcR * (offset < 0 ? 1 : -1)
    let sy = srcCenter.y - srcR * 0.55
    let ex = calloutCenter.x + cos(offset + .pi / 2) * calloutR * (offset < 0 ? 1 : -1)
    let ey = calloutCenter.y + calloutR * 0.92
    line(CGPoint(x: sx, y: sy), CGPoint(x: ex, y: ey), CGColor(gray: 0.45, alpha: 0.55), width: 3)
}
// source ring
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: srcCenter.x - srcR, y: srcCenter.y - srcR, width: srcR * 2, height: srcR * 2))
ctx.setStrokeColor(CGColor(gray: 0.45, alpha: 0.7))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()
// callout body: white ring + shadow, magnified button inside
ctx.saveGState()
shadow(true, blur: 60, dy: -20, alpha: 0.30)
ctx.setFillColor(white)
ctx.addEllipse(in: CGRect(x: calloutCenter.x - calloutR, y: calloutCenter.y - calloutR,
                          width: calloutR * 2, height: calloutR * 2))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: calloutCenter.x - calloutR, y: calloutCenter.y - calloutR,
                          width: calloutR * 2, height: calloutR * 2))
ctx.clip()
// magnified content: paper backdrop + big Export button
ctx.setFillColor(paper)
ctx.fill(CGRect(x: calloutCenter.x - calloutR, y: calloutCenter.y - calloutR,
                width: calloutR * 2, height: calloutR * 2))
let bigBtn = CGRect(x: calloutCenter.x - 170, y: calloutCenter.y - 55, width: 340, height: 110)
ctx.saveGState(); shadow(true, blur: 20, dy: -8, alpha: 0.15)
ctx.setFillColor(violet)
ctx.addPath(CGPath(roundedRect: bigBtn, cornerWidth: 55, cornerHeight: 55, transform: nil))
ctx.fillPath()
ctx.restoreGState()
text("Export", at: CGPoint(x: bigBtn.midX, y: bigBtn.midY), size: 52, weight: .semibold,
     color: .white, centeredAt: true)
ctx.restoreGState()
// white border ring
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: calloutCenter.x - calloutR, y: calloutCenter.y - calloutR,
                          width: calloutR * 2, height: calloutR * 2))
ctx.setStrokeColor(white)
ctx.setLineWidth(10)
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addEllipse(in: CGRect(x: calloutCenter.x - calloutR - 1, y: calloutCenter.y - calloutR - 1,
                          width: calloutR * 2 + 2, height: calloutR * 2 + 2))
ctx.setStrokeColor(CGColor(gray: 0.75, alpha: 0.6))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Write PNG
guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: "site/assets/hero.png")
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(url.path) (\(Int(W))×\(Int(H)))")
