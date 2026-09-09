import AppKit
import PhotonzCore

// Letting a saved text style go on a piece of text (Next, `next-styles` +
// `next-color-drag`). The shelf's side of the same gesture is
// `TextStyleDrag.swift`, and the answer itself is worked out in
// `PhotonzCore/TextStyleDrop.swift`, away from any view.

extension CanvasNSView {

    /// Whether a style can be carried onto the picture at all. The same two
    /// switches the shelf tile reads, so a tile that cannot be picked up is
    /// never met by a canvas that would have taken it.
    var textStyleDropEnabled: Bool {
        Experiments.shared.libraryEnabled
            && Experiments.shared.isEnabled(FeatureCatalog.stylesFlag)
            && Experiments.shared.colorDragEnabled
    }

    /// The saved text style a drag in the air is carrying, nil for everything
    /// else. Its own pasteboard type, so a style and a component and a file can
    /// never be mistaken for one another.
    func droppedTextStyle(_ sender: NSDraggingInfo) -> TextStyleDrop.SavedStyle? {
        guard textStyleDropEnabled else { return nil }
        return TextStyleDrag.payload(on: sender.draggingPasteboard)
    }

    /// Follows a style across the picture: works out what is under the pointer,
    /// outlines the text that would take it, and says in one line what letting
    /// go would do. A drop that would do nothing is refused with the ordinary
    /// no-entry pointer, and STILL says why, because a canvas that quietly
    /// refuses is the thing this exists to stop.
    func trackTextStyleDrag(_ style: TextStyleDrop.SavedStyle,
                            atViewPoint viewPoint: CGPoint) -> NSDragOperation {
        let reading = textStyleReading(style, atViewPoint: viewPoint)
        dropLanding = nil
        dropHostBox = nil
        textStyleDropBoxes = reading.answer.lands ? reading.boxes : []
        showTextStyleNote(reading.answer, at: viewPoint)
        refreshOverlays()
        return reading.answer.lands ? .copy : []
    }

    /// Lands the style on whatever the tracking promised. Internal so a walk
    /// can let one go without synthesising a drag session.
    func dropTextStyle(_ style: TextStyleDrop.SavedStyle, atViewPoint viewPoint: CGPoint) -> Bool {
        let reading = textStyleReading(style, atViewPoint: viewPoint)
        guard reading.answer.lands, !reading.layerIDs.isEmpty else { return false }
        onDropTextStyle(style.id, reading.layerIDs)
        return true
    }

    /// Everything the canvas knows about a style held at a point: what letting
    /// go would do, which text it would reach, and the box to outline.
    ///
    /// Aiming at text that is already picked reaches every picked piece of
    /// text, the way a colour let go on a swatch paints everything that swatch
    /// speaks for. Aiming at text nobody picked reaches only that text, because
    /// the pointer named it.
    private func textStyleReading(_ style: TextStyleDrop.SavedStyle, atViewPoint viewPoint: CGPoint)
    -> (answer: TextStyleDrop.Answer, layerIDs: [UUID], boxes: [CGRect]) {
        guard let viewport, let document else {
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: nil, isText: false)),
                    [], [])
        }
        let point = viewport.documentPoint(fromView: viewPoint)
        guard let hit = document.canvasHitTest(point, zoom: viewport.zoom) else {
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: nil, isText: false)),
                    [], [])
        }
        guard hit.textTreatment != nil else {
            // A copy of a component is hit whole, contents and all, so words
            // inside one arrive here looking like anything else that is not
            // text. Saying so over the top of readable words is a lie, so the
            // one line names the piece and its original instead, and points at
            // the two moves that work. The rule does not change: nothing lands
            // inside a copy, because the next sync would write it straight back
            // over.
            let copyPiece = componentsEnabled
                ? document.textStyleCopyPiece(at: point, zoom: viewport.zoom) : nil
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: hit.name, isText: false,
                                                                  copyPiece: copyPiece)),
                    [], [])
        }
        // Everything the drop would reach: the text under the pointer alone,
        // or the whole picked crowd when the pointer is aimed at one of them.
        var reached = [hit.id]
        if pickedLayerIDs.contains(hit.id) {
            let picked = document.allLayers
                .filter { pickedLayerIDs.contains($0.id) && $0.textTreatment != nil }
                .map(\.id)
            if picked.count > 1 { reached = picked }
        }
        // A crowd where some already wear the style still has work to do, so
        // the no-op refusal only speaks for the one piece of text being named.
        let target = TextStyleDrop.Target(
            name: hit.name, isText: true,
            wearingID: reached.count > 1 ? nil : hit.textStyleID,
            wearingName: reached.count > 1 ? nil
                : hit.textStyleID.flatMap { document.textStyle(id: $0)?.name },
            reaches: reached.count)
        let boxes = reached.compactMap { document.canvasLayer(id: $0)?.frame }
        return (TextStyleDrop.answer(dropping: style, on: target), reached, boxes)
    }

    // MARK: - The line the canvas says while a style is in the air

    /// Puts the sentence under the pointer, or takes it away.
    ///
    /// It is words rather than a ring alone because a ring can only say yes.
    /// Half of what somebody carrying a style needs to hear is a no with a
    /// reason: this is not text, or it is already wearing this. A tip cannot
    /// show while a drag is in the air, so the canvas draws its own.
    private func showTextStyleNote(_ answer: TextStyleDrop.Answer, at viewPoint: CGPoint) {
        textStyleDropNote = answer.note
        let font = Self.dropNoteFont
        let inset = CGSize(width: 9, height: 4)
        let text = CGSize(width: (answer.note as NSString)
                            .size(withAttributes: [.font: font]).width.rounded(.up),
                          height: (font.ascender - font.descender).rounded(.up))
        let box = CGSize(width: text.width + inset.width * 2,
                         height: text.height + inset.height * 2)
        // Below and to the right of the pointer, clear of the chip riding under
        // it, and nudged back inside the view rather than drawn off the edge.
        var origin = CGPoint(x: viewPoint.x + 16, y: viewPoint.y + 26)
        origin.x = min(max(4, origin.x), max(4, bounds.maxX - box.width - 4))
        origin.y = min(max(4, origin.y), max(4, bounds.maxY - box.height - 4))
        // Accent for a style that lands, a plain dark plate for one that does
        // not: the colour repeats what the words say, so a glance is enough
        // and reading is only needed for the why.
        dropNoteLayer.fillColor = (answer.lands
            ? NSColor.controlAccentColor
            : NSColor.black.withAlphaComponent(0.78)).cgColor
        dropNoteLayer.frame = bounds
        dropNoteLayer.path = CGPath(roundedRect: CGRect(origin: origin, size: box),
                                    cornerWidth: box.height / 2,
                                    cornerHeight: box.height / 2, transform: nil)
        dropNoteTextLayer.string = answer.note
        dropNoteTextLayer.font = font
        dropNoteTextLayer.fontSize = font.pointSize
        dropNoteTextLayer.foregroundColor = NSColor.white.cgColor
        dropNoteTextLayer.alignmentMode = .center
        dropNoteTextLayer.contentsScale = window?.backingScaleFactor ?? 2
        dropNoteTextLayer.frame = CGRect(x: origin.x + inset.width, y: origin.y + inset.height,
                                         width: text.width, height: text.height)
        dropNoteLayer.isHidden = false
    }

    /// Takes the sentence and the outlines away, whichever way the drag ended.
    func clearTextStyleNote() {
        textStyleDropNote = nil
        textStyleDropBoxes = []
        dropNoteLayer.isHidden = true
    }

    static let dropNoteFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
}
