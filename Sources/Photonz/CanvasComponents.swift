import AppKit
import PhotonzCore

/// The mark a main component wears on the canvas (Next, `next-components`).
///
/// A component that looked exactly like an ordinary group would be a component
/// you could only find out about by opening a panel. So every main carries its
/// name above its top left corner in the component violet, with the four
/// diamond glyph in front of it: the same mark the layers list and the Library
/// tile use, so it is recognisable wherever you meet it.
///
/// It is chrome, not pixels: drawn by the canvas above the picture, the same
/// size at every zoom, and never in an export. A frame that has been promoted
/// shows this INSTEAD of its frame label, so a box never wears two names.
extension CanvasNSView {

    private static let componentLabelGap: CGFloat = 4
    private static let componentLabelHeight: CGFloat = 14
    private static let componentGlyphSize: CGFloat = 10

    /// Whether component chrome is drawn at all. A document with no components
    /// in it never sees any of this, which is every screenshot anybody has
    /// taken.
    var componentsEnabled: Bool { Experiments.shared.componentsEnabled }

    /// The mains this canvas should mark, empty when the flag is off or the
    /// document holds none. Also read by the frame chrome, so a promoted frame
    /// drops its own label rather than printing the name twice.
    var markedComponents: [Layer] {
        guard componentsEnabled, let document else { return [] }
        return document.mainComponents.filter(\.isVisible)
    }

    func refreshComponentChrome() {
        let mains = markedComponents
        guard let viewport, let document, !mains.isEmpty else {
            componentChromeLayer.isHidden = true
            componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            return
        }
        componentChromeLayer.isHidden = false
        componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for main in mains {
            guard let bounds = document.canvasBounds(of: main.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            let top = rect.minY - Self.componentLabelHeight - Self.componentLabelGap

            let glyph = CAShapeLayer()
            let box = CGRect(x: rect.minX,
                             y: top + (Self.componentLabelHeight - Self.componentGlyphSize) / 2,
                             width: Self.componentGlyphSize, height: Self.componentGlyphSize)
            glyph.path = ComponentGlyph.path(in: box)
            glyph.fillColor = ComponentGlyph.cgColor
            glyph.frame = layer?.bounds ?? rect
            componentChromeLayer.addSublayer(glyph)

            let label = CATextLayer()
            label.string = main.name
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.fontSize = 10
            // The component violet, not a theme label color and not the
            // selection accent: this text sits on top of whatever picture is
            // open, and the accent already means "selected".
            label.foregroundColor = ComponentGlyph.cgColor
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            let x = rect.minX + Self.componentGlyphSize + 4
            label.frame = CGRect(x: x, y: top,
                                 width: max(min(rect.width, 240), 40),
                                 height: Self.componentLabelHeight)
            componentChromeLayer.addSublayer(label)
        }
    }
}
