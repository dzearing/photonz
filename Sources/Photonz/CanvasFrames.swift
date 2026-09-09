import AppKit
import PhotonzCore

/// What a frame looks like on the canvas beyond the pixels it paints (Next,
/// `next-frames`).
///
/// Two pieces of chrome, and both are chrome: they are drawn by the canvas, not
/// by the renderer, so they sit above the picture, stay the same size at every
/// zoom, and never land in an export.
///
/// - **Its name, above its top left corner.** A screen with no label is a white
///   rectangle; the label is how a canvas of several screens stays readable.
///   The name is also the frame's handle: what a click on it does lives in
///   `CanvasNames.swift`, next to the component name that behaves the same way.
/// - **A hairline at its edge.** A frame whose surface matches the canvas
///   behind it would otherwise have no edge at all, and the edge is the thing
///   the whole feature is about.
extension CanvasNSView {

    // MARK: Where a frame is RIGHT NOW

    /// A layer's box on the canvas as the hand has it this instant, drag and
    /// all. The one door every piece of frame chrome reads its geometry
    /// through.
    ///
    /// A preview drag never touches the document: `previewLayerFrame` re-renders
    /// the picture through `submit` without recording anything, so `document`
    /// goes on holding the pre-drag box until mouse-up. The picture is live
    /// — the surface grows, the contents clip — but chrome asking the document
    /// where the frame is gets told where it WAS, and stands still for the
    /// whole gesture.
    ///
    /// That is invisible for most things and fatal for a frame. A frame's
    /// surface is usually the same white as the canvas behind it, so its edge
    /// hairline is the only thing on screen saying where its boundary is; with
    /// the blue outline and the eight handles both hidden for the duration of a
    /// resize, a frozen hairline means a drag with NOTHING moving in it.
    /// Reported by the user on 2026-09-09: "when i try to resize a frame, it
    /// has no live feedback". Measured at the time: the canvas was redrawing 42
    /// times a second throughout, one composite per pointer move. Every one of
    /// them was drawn under an edge that had not moved.
    func liveCanvasBounds(of id: UUID) -> CGRect? {
        if let resizeDrag, resizeDrag.layerID == id { return resizeDrag.frame }
        if let moveDrag, moveDrag.moved, moveDrag.layerID == id, !moveDrag.copying {
            return CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        }
        // A ⌥-drag leaves the original where it is and carries a copy that has
        // no id yet, so the frame this asks about is the one standing still.
        if multiMove?.copying != true, let origin = multiMove?.liveOrigins?[id],
           let box = document?.canvasBounds(of: id) {
            return CGRect(origin: origin, size: box.size)
        }
        return document?.canvasBounds(of: id)
    }

    // MARK: Drawing

    func refreshFrameChrome() {
        guard framesEnabled, let viewport, let document, document.hasFrames else {
            frameChromeLayer.isHidden = true
            frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            frameEdgeLayer.isHidden = true
            layoutCanvasNameField()
            return
        }
        frameChromeLayer.isHidden = false
        frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let edges = CGMutablePath()
        for frame in document.frames {
            guard frame.isVisible, let bounds = liveCanvasBounds(of: frame.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            edges.addRect(viewRect(forDocRect: bounds, in: viewport).insetBy(dx: 0.5, dy: 0.5))
        }

        // Names come from the one stacked list, so a screen whose corner is
        // crowded prints its name on the line the list gave it rather than on
        // top of whatever else wanted that spot. A frame promoted to a
        // component is not in this list at all: it wears the component's mark
        // and name in the same place, so a box never carries two names.
        for chip in canvasNameChips() where chip.kind == .screen {
            // The frame being renamed has a field standing where its name was.
            if chip.layer.id == canvasRenameID { continue }
            let label = CATextLayer()
            label.string = chip.layer.name
            label.font = Self.nameLabelFont
            label.fontSize = Self.nameLabelFont.pointSize
            // A neutral grey, NOT a theme label color: this text sits on the
            // picture, which may be white, dark, or a screenshot of anything,
            // and a label that follows the app's theme goes invisible on half
            // of them. The accent means "this name is live": the frame is
            // selected, or the pointer is resting on the name, which is the
            // only hint anywhere that the name can be clicked.
            label.foregroundColor = isNameLabelLive(chip.layer.id)
                ? NSColor.controlAccentColor.cgColor
                : CGColor(gray: 0.45, alpha: 1)
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            // The label hangs above the frame's top left corner and is never
            // part of it: it does not move the frame, and clicking through it
            // reaches whatever is behind.
            label.frame = CanvasNameLabels.box(for: chip.label)
            frameChromeLayer.addSublayer(label)
        }
        frameEdgeLayer.path = edges
        frameEdgeLayer.isHidden = edges.isEmpty
        layoutCanvasNameField()
    }

    /// Whether frame chrome is drawn at all. A document with no frames in it
    /// never sees any of this, which is every screenshot anybody has taken.
    var framesEnabled: Bool { Experiments.shared.framesEnabled }
}
