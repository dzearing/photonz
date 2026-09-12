import AppKit
import PhotonzCore

/// The mark a main component wears on the canvas (Next, `next-components`).
///
/// A component that looked exactly like an ordinary group would be a component
/// you could only find out about by opening a panel. So every main carries one
/// word above its top left corner in the component violet, with the four
/// diamond glyph in front of it: the same mark the layers list and the Library
/// tile use, so it is recognisable wherever you meet it. The word is the
/// component's name, or, once the component has more than one drawing on the
/// canvas, which version this drawing is (`CanvasNameLabels.caption`).
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
        //
        // The drawing you are looking at goes on LAST, over everything else in
        // the strip: it is the only one wider than the room the row gave it, so
        // it is the only one that can land on a neighbour, and it has to be the
        // one on top when it does.
        let chips = canvasNameChips().filter { $0.kind != .screen }
        for chip in chips where !chip.spelledOut { drawNameChip(chip) }
        for chip in chips where chip.spelledOut { drawNameChip(chip) }
    }

    /// One chip drawn into the strip: its mark, and the word it is saying right
    /// now, on a plate when the word only appeared because you are looking.
    private func drawNameChip(_ chip: CanvasNameChip) {
        let strip = CanvasNameLabels.box(forFrameRect: chip.label.frameRect)
        let renaming = chip.layer.id == canvasRenameID

        // What this chip puts on the canvas right now. Usually the word it is
        // saying; while it is being renamed, only the words the typing will
        // NOT replace, because the field stands over the rest. On a drawing
        // reading "Save button \u{00B7} Disabled" that leaves "Save button
        // \u{00B7} " printed and the box sitting on "Disabled", so which of the
        // two words is being renamed is plain before anything is typed.
        let printed = renaming ? canvasRenamePrefix(of: chip.layer.id) : chip.word

        // A name that is only there because you are looking gets something to
        // be read against. Where the names sit was decided by what they say at
        // REST, so this one is wider than the room it was given and may reach
        // over a neighbour's mark; a plate under it means it lands as a chip on
        // top rather than as a smear.
        if chip.spelledOut, let word = printed {
            let text = CanvasNameLabels.box(for: chip.label)
            let plate = CALayer()
            plate.frame = CGRect(x: strip.minX - 4, y: strip.minY - 1,
                                 width: (text.minX - strip.minX) + Self.captionWidth(word) + 8,
                                 height: strip.height + 2)
            plate.cornerRadius = 4
            // Resolved through the canvas's own appearance rather than
            // whatever happens to be current: a light plate behind violet
            // letters in a dark app would be a flare on the picture.
            var backing = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                backing = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
            }
            plate.backgroundColor = backing
            componentChromeLayer.addSublayer(plate)
        }

        // The mark stays put through a rename: it says what kind of thing
        // this is, and that does not change while you are typing.
        let glyph = CAShapeLayer()
        let box = CGRect(x: strip.minX,
                         y: strip.minY + (strip.height - Self.componentGlyphSize) / 2,
                         width: Self.componentGlyphSize, height: Self.componentGlyphSize)
        // One diamond for a copy, not the original's four: a different shape
        // rather than a different weight, so it still reads at ten points.
        glyph.path = chip.kind == .component
            ? ComponentGlyph.path(in: box)
            : ComponentGlyph.instancePath(in: box)
        glyph.fillColor = ComponentGlyph.cgColor
        glyph.frame = layer?.bounds ?? strip
        componentChromeLayer.addSublayer(glyph)

        // A copy of the first version wears its mark and nothing else, until
        // you look at it: a screen built out of twelve ordinary buttons would
        // otherwise carry twelve labels all saying the same word. A name being
        // renamed with nothing kept in front of the field draws nothing either:
        // the field is standing exactly where the word was.
        guard let word = printed else { return }

        // The component violet at rest, the selection accent when the word is
        // live: the mark in front of it goes on saying "component", so the word
        // is free to say "selected, or under your pointer" the same way a
        // screen's name does. Neither is a theme label color: this text sits on
        // top of whatever picture is open.
        // A copy's version is a caption rather than a handle, so it stays in the
        // component violet however the copy is picked and the accent goes on
        // meaning "this word answers a click".
        // Words kept in front of an open field stay violet however the drawing
        // is picked: the accent means "this answers a click", and right now the
        // thing answering is the box, not the name standing beside it.
        let ink = !renaming && chip.kind == .component && isNameLabelLive(chip.layer.id)
            ? NSColor.controlAccentColor.cgColor
            : ComponentGlyph.cgColor
        componentChromeLayer.addSublayer(nameTextLayer(
            word, color: ink, frame: CanvasNameLabels.box(for: chip.label)))
    }

    /// The one word of canvas chrome above a drawing, drawn the same way for a
    /// name and for a version so both sit on one line with one baseline.
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
