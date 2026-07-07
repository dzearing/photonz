import AppKit

/// Draws the status-item icon, optionally with a corner dot signalling "update
/// available" (17.10). The glyph is the product icon's aperture (same ring +
/// six-blade geometry as `Scripts/make-icon.swift`), hand-drawn as a template
/// image so it renders in the menu bar's own tint — matching the app icon's
/// identity instead of the stock `camera.viewfinder` symbol.
enum MenuBarIcon {
    @MainActor static func image(updateAvailable: Bool) -> NSImage {
        let side: CGFloat = 18
        let icon = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAperture(in: rect, context: ctx)
            if updateAvailable {
                // Punch a gap so the dot reads as a badge, then fill the dot.
                let dot: CGFloat = 5
                let gap = NSRect(x: rect.maxX - dot - 1.5, y: rect.maxY - dot - 1.5,
                                 width: dot + 3, height: dot + 3)
                ctx.clear(gap.intersection(rect))
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - dot, y: rect.maxY - dot,
                                            width: dot, height: dot)).fill()
            }
            return true
        }
        icon.isTemplate = true
        icon.accessibilityDescription = updateAvailable ? "\(AppInfo.name), update available" : AppInfo.name
        return icon
    }

    /// The app icon's aperture at menu-bar scale: a ring with six blades drawn
    /// from the rim toward the middle, clipped inside the ring. Ratios mirror
    /// the product icon (blade end at 0.42 of the radius, sweep of 1.55·60°);
    /// stroke weights are tuned up slightly so the glyph holds at 18 pt.
    private static func drawAperture(in rect: NSRect, context ctx: CGContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width * 0.40
        let lineWidth = rect.width * 0.075

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(lineWidth)
        let ring = CGRect(x: center.x - outer, y: center.y - outer,
                          width: outer * 2, height: outer * 2)
        ctx.strokeEllipse(in: ring)

        ctx.saveGState()
        ctx.addEllipse(in: ring.insetBy(dx: lineWidth * 0.30, dy: lineWidth * 0.30))
        ctx.clip()
        ctx.setLineWidth(lineWidth)
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let start = CGPoint(x: center.x + cos(angle) * outer,
                                y: center.y + sin(angle) * outer)
            let endAngle = angle + .pi / 3 * 1.55
            let end = CGPoint(x: center.x + cos(endAngle) * outer * 0.42,
                              y: center.y + sin(endAngle) * outer * 0.42)
            ctx.move(to: start)
            ctx.addLine(to: end)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
