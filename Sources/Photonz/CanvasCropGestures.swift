import AppKit
import PhotonzCore

// The Crop tool's gestures, past the press (`mouseDown` decides which of the
// three a press is, through `Crop.press`):
//
// - a drag anywhere off a handle draws the box you want, from the press to the
//   pointer, inside the current box as much as outside it; ⌥ draws it out from
//   the press, ⇧ keeps it square (or the locked aspect);
// - Space held while drawing slides the box being drawn, the way a marquee
//   moves under Space in Photoshop and Preview, and letting it go carries on
//   drawing from where the box now is;
// - Space held at rest turns the pointer into an open hand, and a press then
//   carries the box;
// - the arrow keys nudge the box, ⇧ by ten.
//
// The user, 2026-11-03: "what I really want to do is select a box, rather than
// resize a box". All the geometry is `Crop`, in PhotonzCore, where it is tested.

extension CanvasNSView {

    /// One move of a crop drag that has left the click tolerance.
    func cropDragged(_ drag: inout CropDrag, to p: CGPoint) {
        guard let viewport else { return }
        let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
        let delta = CGPoint(x: p.x - drag.lastPoint.x, y: p.y - drag.lastPoint.y)
        switch drag.kind {
        case .resize(let handle):
            guard let start = drag.startRect else { return }
            cropRect = Crop.resize(start, dragging: handle, to: p, aspect: cropAspect, bounds: bounds)
        case .move:
            if let rect = cropRect { cropRect = Crop.moved(rect, by: delta, in: bounds) }
        case .define(let anchor):
            if cropSpaceHeld, let rect = cropRect, cropRect != drag.startRect {
                let slid = Crop.slidDraw(anchor: anchor, rect: rect, by: delta, in: bounds)
                drag.kind = .define(anchor: slid.anchor)
                cropRect = slid.rect
            } else {
                cropRect = cropDrawnRect(anchor: anchor, to: p) ?? drag.startRect
            }
        }
    }

    /// The box a draw from `anchor` to `p` makes under the keys held now.
    private func cropDrawnRect(anchor: CGPoint, to p: CGPoint) -> CGRect? {
        guard let viewport else { return nil }
        let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
        // ⌥ and ⇧ belong to the drawing gesture; Current draws as it always has.
        let keys = Experiments.shared.cropDrawsABoxEnabled
        return Crop.drawnRect(anchor: anchor, current: p, aspect: cropAspect,
                              fromCenter: keys && pointerModifiers.contains(.option),
                              square: keys && pointerModifiers.contains(.shift), bounds: bounds)
    }

    /// ⌥ or ⇧ pressed or let go with a box half drawn redraws it there and
    /// then, the way a shape tool does: a hand checking which it wants holds
    /// the pointer still to see.
    func cropFlagsChanged() {
        guard tool == .crop, let drag = cropDrag, drag.moved, !cropSpaceHeld,
              case .define(let anchor) = drag.kind else { return }
        cropRect = cropDrawnRect(anchor: anchor, to: drag.lastPoint) ?? drag.startRect
        refreshOverlays()
    }

    /// The keys the Crop tool answers before anything else in the window:
    /// Space (held, it moves) and the arrows (nudge the box). True when the
    /// key was taken.
    func cropKeyDown(_ event: NSEvent) -> Bool {
        guard tool == .crop, Experiments.shared.cropDrawsABoxEnabled else { return false }
        let chordFree = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        if event.keyCode == 49, chordFree {
            // A held key repeats; only the first press changes anything.
            if !cropSpaceHeld { setCropSpaceHeld(true) }
            return true
        }
        if chordFree, cropDrag == nil, let rect = cropRect, let viewport,
           let delta = Nudge.delta(keyCode: event.keyCode, large: event.modifierFlags.contains(.shift)) {
            let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
            let moved = Crop.moved(rect, by: CGPoint(x: delta.dx, y: delta.dy), in: bounds)
            cropRect = moved
            onCropRectChange(moved)
            refreshOverlays()
            return true
        }
        return false
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, cropSpaceHeld {
            setCropSpaceHeld(false)
            return
        }
        super.keyUp(with: event)
    }

    /// Space went down or came up. A box being drawn picks the change up on
    /// the next move; at rest the pointer says what a press will do now.
    func setCropSpaceHeld(_ held: Bool) {
        cropSpaceHeld = held
        // A carry in hand keeps its closed hand until the button comes up.
        if let drag = cropDrag, case .move = drag.kind { return }
        refreshGrabCursor()
    }
}
