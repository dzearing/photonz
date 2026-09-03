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
///
/// The name is a handle, exactly like a screen's name: click it to pick the
/// component, double click it to rename it where it sits. That behaviour is
/// shared with screens and lives in `CanvasNames.swift`.
extension CanvasNSView {

    static let componentGlyphSize: CGFloat = 10

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

    /// The copies this canvas should mark. They get the glyph and NO name: a
    /// screen built out of twelve buttons would otherwise wear twelve labels,
    /// and the name of a copy is already in the layers list and the dock.
    var markedComponentInstances: [Layer] {
        guard componentsEnabled, let document else { return [] }
        return document.allLayers.filter { $0.isComponentInstance && $0.isVisible }
    }

    func refreshComponentChrome() {
        let mains = markedComponents
        let copies = markedComponentInstances
        guard let viewport, let document, !mains.isEmpty || !copies.isEmpty else {
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
            let strip = CanvasNameLabels.box(forFrameRect: rect)

            // The mark stays put through a rename: it says what kind of thing
            // this is, and that does not change while you are typing.
            let glyph = CAShapeLayer()
            let box = CGRect(x: strip.minX,
                             y: strip.minY + (strip.height - Self.componentGlyphSize) / 2,
                             width: Self.componentGlyphSize, height: Self.componentGlyphSize)
            glyph.path = ComponentGlyph.path(in: box)
            glyph.fillColor = ComponentGlyph.cgColor
            glyph.frame = layer?.bounds ?? rect
            componentChromeLayer.addSublayer(glyph)

            // The component being renamed has a field standing where its name
            // was, so the name itself is not drawn twice.
            if main.id == canvasRenameID { continue }

            let label = CATextLayer()
            label.string = main.name
            label.font = Self.nameLabelFont
            label.fontSize = Self.nameLabelFont.pointSize
            // The component violet at rest, the selection accent when the name
            // is live: the mark in front of it goes on saying "component", so
            // the name is free to say "selected, or under your pointer" the
            // same way a screen's name does. Neither is a theme label color:
            // this text sits on top of whatever picture is open.
            label.foregroundColor = isNameLabelLive(main.id)
                ? NSColor.controlAccentColor.cgColor
                : ComponentGlyph.cgColor
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            label.frame = CanvasNameLabels.box(forFrameRect: rect,
                                               leadingInset: Self.componentMarkInset)
            componentChromeLayer.addSublayer(label)
        }

        for copy in copies {
            guard let bounds = document.canvasBounds(of: copy.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            let glyph = CAShapeLayer()
            let box = CGRect(x: rect.minX,
                             y: rect.minY - Self.componentGlyphSize - CanvasNameLabels.gap,
                             width: Self.componentGlyphSize, height: Self.componentGlyphSize)
            // One diamond, not the original's four: a different shape rather
            // than a different weight, so it still reads at ten points.
            glyph.path = ComponentGlyph.instancePath(in: box)
            glyph.fillColor = ComponentGlyph.cgColor
            glyph.frame = layer?.bounds ?? rect
            componentChromeLayer.addSublayer(glyph)
        }
    }
}
