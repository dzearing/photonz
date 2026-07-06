import AppKit

/// Draws the status-item icon, optionally with a corner dot signalling "update
/// available" (17.10). Drawn as a template image (alpha-only), so the dot
/// renders in the menu bar's own tint like the glyph itself — SwiftUI overlays
/// get flattened unreliably inside `MenuBarExtra`, hand-drawing doesn't.
enum MenuBarIcon {
    @MainActor static func image(updateAvailable: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "Photonz")?
            .withSymbolConfiguration(config) else { return NSImage() }
        symbol.isTemplate = true
        guard updateAvailable else { return symbol }

        let size = symbol.size
        let badged = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            // Punch a small gap so the dot reads as a badge, then fill the dot.
            let dot: CGFloat = 5
            let gap = NSRect(x: rect.maxX - dot - 1.5, y: rect.maxY - dot - 1.5,
                             width: dot + 3, height: dot + 3)
            NSGraphicsContext.current?.cgContext.clear(gap.intersection(rect))
            let dotRect = NSRect(x: rect.maxX - dot, y: rect.maxY - dot, width: dot, height: dot)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        badged.isTemplate = true
        badged.accessibilityDescription = "Photonz — update available"
        return badged
    }
}
