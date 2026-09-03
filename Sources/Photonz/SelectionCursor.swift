import AppKit
import PhotonzCore

/// Crosshair cursors for the region selection tools, with a corner badge
/// showing the LIVE combine mode — hold ⇧ and the cursor grows a "+" (add),
/// ⌥ a "−" (subtract), ⇧⌥ an "×" (intersect) — so you can see what the next
/// drag or wand click will do before starting it (Photoshop behavior).
@MainActor
enum SelectionCursor {
    private static var cache: [SelectionRegion.Mode: NSCursor] = [:]

    static func cursor(for mode: SelectionRegion.Mode) -> NSCursor {
        if let hit = cache[mode] { return hit }
        let built = build(mode)
        cache[mode] = built
        // Drawn pointers are not shared singletons, so they have to say their
        // own name for a playtest to be able to read them.
        CanvasCursor.register(built, as: "select-" + String(describing: mode))
        return built
    }

    private static func build(_ mode: SelectionRegion.Mode) -> NSCursor {
        let size = NSSize(width: 28, height: 28)
        let center = NSPoint(x: 9, y: 9)
        let image = NSImage(size: size, flipped: true) { _ in
            func strokeCross(_ color: NSColor, _ width: CGFloat) {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: center.x - 8, y: center.y))
                path.line(to: NSPoint(x: center.x + 8, y: center.y))
                path.move(to: NSPoint(x: center.x, y: center.y - 8))
                path.line(to: NSPoint(x: center.x, y: center.y + 8))
                path.lineWidth = width
                color.setStroke()
                path.stroke()
            }
            // White halo under the black cross so it reads on dark canvases.
            strokeCross(.white, 3)
            strokeCross(.black, 1)
            if let badge = badgeGlyph(mode) {
                let font = NSFont.systemFont(ofSize: 11, weight: .heavy)
                let glyph = NSString(string: badge)
                let at = NSPoint(x: 17, y: 11)
                glyph.draw(at: at, withAttributes: [
                    .font: font, .foregroundColor: NSColor.white,
                    .strokeColor: NSColor.white, .strokeWidth: 10.0, // halo pass
                ])
                glyph.draw(at: at, withAttributes: [
                    .font: font, .foregroundColor: NSColor.black,
                ])
            }
            return true
        }
        // Hotspot at the crosshair center (top-left origin).
        return NSCursor(image: image, hotSpot: center)
    }

    private static func badgeGlyph(_ mode: SelectionRegion.Mode) -> String? {
        switch mode {
        case .replace: nil
        case .add: "+"
        case .subtract: "−"
        case .intersect: "×"
        }
    }
}
