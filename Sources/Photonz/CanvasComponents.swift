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

            // The component being renamed has a field standing where its name
            // was, so nothing is drawn under it.
            if chip.layer.id == canvasRenameID { continue }

            // The component violet at rest, the selection accent when the name
            // is live: the mark in front of it goes on saying "component", so
            // the name is free to say "selected, or under your pointer" the
            // same way a screen's name does. Neither is a theme label color:
            // this text sits on top of whatever picture is open.
            // A copy's version is a caption rather than a handle: it stays in
            // the component violet however the copy is picked, so the accent
            // goes on meaning "this word answers a click".
            let ink = chip.kind == .component && isNameLabelLive(chip.layer.id)
                ? NSColor.controlAccentColor.cgColor
                : ComponentGlyph.cgColor
            // Where the letters go: the strip with the mark's room taken off
            // the front.
            let text = CanvasNameLabels.box(for: chip.label)

            // The version keeps its own width and the NAME gives way, the same
            // rule the layers list follows: every version of a component
            // carries the same name, so on a small box the version is the word
            // that tells two drawings apart and must not be the one squeezed.
            let versionWidth = min(Self.versionWidth(chip.version), text.width)
            let room = text.width - versionWidth - (versionWidth > 0 ? Self.versionGap : 0)

            // A copy gets the mark and NO name: a screen built out of twelve
            // buttons would otherwise wear twelve labels, and the name of a
            // copy is already in the layers list and the dock.
            var nameWidth: CGFloat = 0
            if chip.kind == .component, room > 0 {
                nameWidth = min((chip.layer.name as NSString)
                    .size(withAttributes: [.font: Self.nameLabelFont]).width.rounded(.up), room)
                componentChromeLayer.addSublayer(nameTextLayer(
                    chip.layer.name, color: ink,
                    frame: CGRect(x: text.minX, y: text.minY,
                                  width: room, height: text.height)))
            }

            // What version this drawing is, when its component holds more than
            // one. Dimmer than the name it follows on an original, full
            // strength on a copy where it is the only word there is.
            guard let version = chip.version, versionWidth > 0 else { continue }
            let start = text.minX + (nameWidth > 0 ? nameWidth + Self.versionGap : 0)
            componentChromeLayer.addSublayer(nameTextLayer(
                (nameWidth > 0 ? Self.versionSeparator : "") + version,
                color: nameWidth > 0 ? (ink.copy(alpha: 0.7) ?? ink) : ink,
                frame: CGRect(x: start, y: text.minY,
                              width: max(text.maxX - start, 0), height: text.height)))
        }
    }

    /// One run of canvas chrome text, drawn the same way every time so a name
    /// and the version after it sit on one line with one baseline.
    private func nameTextLayer(_ string: String, color: CGColor, frame: CGRect) -> CATextLayer {
        let label = CATextLayer()
        label.string = string
        label.font = Self.nameLabelFont
        label.fontSize = Self.nameLabelFont.pointSize
        label.foregroundColor = color
        label.contentsScale = window?.backingScaleFactor ?? 2
        label.alignmentMode = .left
        label.truncationMode = .end
        label.frame = frame
        return label
    }
}
