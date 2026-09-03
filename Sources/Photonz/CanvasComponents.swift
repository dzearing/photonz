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
        guard viewport != nil, document != nil,
              !markedComponents.isEmpty || !markedComponentInstances.isEmpty else {
            componentChromeLayer.isHidden = true
            componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            return
        }
        componentChromeLayer.isHidden = false
        componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Where a name goes is decided once, for every chip in the strip at
        // the top of the boxes, so a component in a screen's corner sits on a
        // clear line instead of over the screen's name.
        for chip in canvasNameChips() where chip.kind != .screen {
            let strip = CanvasNameLabels.box(forFrameRect: chip.label.frameRect)

            // The mark stays put through a rename: it says what kind of thing
            // this is, and that does not change while you are typing.
            let glyph = CAShapeLayer()
            let box = CGRect(x: strip.minX,
                             y: strip.minY + (strip.height - Self.componentGlyphSize) / 2,
                             width: Self.componentGlyphSize, height: Self.componentGlyphSize)
            // One diamond for a copy, not the original's four: a different
            // shape rather than a different weight, so it still reads at ten
            // points.
            glyph.path = chip.kind == .component
                ? ComponentGlyph.path(in: box)
                : ComponentGlyph.instancePath(in: box)
            glyph.fillColor = ComponentGlyph.cgColor
            glyph.frame = layer?.bounds ?? strip
            componentChromeLayer.addSublayer(glyph)

            // A copy gets the mark and NO name: a screen built out of twelve
            // buttons would otherwise wear twelve labels, and the name of a
            // copy is already in the layers list and the dock.
            guard chip.kind == .component else { continue }
            // The component being renamed has a field standing where its name
            // was, so the name itself is not drawn twice.
            if chip.layer.id == canvasRenameID { continue }

            let label = CATextLayer()
            label.string = chip.layer.name
            label.font = Self.nameLabelFont
            label.fontSize = Self.nameLabelFont.pointSize
            // The component violet at rest, the selection accent when the name
            // is live: the mark in front of it goes on saying "component", so
            // the name is free to say "selected, or under your pointer" the
            // same way a screen's name does. Neither is a theme label color:
            // this text sits on top of whatever picture is open.
            label.foregroundColor = isNameLabelLive(chip.layer.id)
                ? NSColor.controlAccentColor.cgColor
                : ComponentGlyph.cgColor
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            label.frame = CanvasNameLabels.box(for: chip.label)
            componentChromeLayer.addSublayer(label)
        }
    }
}
