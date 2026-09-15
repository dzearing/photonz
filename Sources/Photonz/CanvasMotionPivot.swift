import AppKit
import PhotonzCore
import SwiftUI

// The pivot on the canvas (Next, `next-motion`): the point a turning layer
// turns around, drawn where it is and dragged to where it should be.
//
// A bell that swings hangs from its MOUNT, not from its middle. Put the pivot
// in the middle and the top of the bell swings one way while the bottom swings
// the other, which reads as a bobblehead: nothing about the two angles is
// wrong, the pivot is. The right pivot is a point on YOUR drawing and nobody
// but you knows where it is, which is why this is a handle rather than a
// preset, and why it is on the picture from the moment a turn exists rather
// than behind a mode you have to know to switch into.
//
// Everything that decides WHERE the point is lives in `MotionPivot`
// (PhotonzCore) and is tested there. This file converts between the view and
// the layer's own box, draws, and hands one finished move to the editor.

/// What the canvas is showing a pivot for, worked out by the editor so the
/// canvas never has to know what a motion is.
struct MotionPivotHandle: Equatable {
    let layerID: UUID
    let motionID: UUID
    /// Where it sits now, in document points.
    let point: CGPoint
    /// The layer's own box, which is what the pivot is a fraction of: a drag
    /// hands a place back and this is what turns it into one.
    let box: CGRect
}

/// The handle under the hand.
struct MotionPivotDrag {
    let handle: MotionPivotHandle
    /// Where the pointer is now, in document points.
    var current: CGPoint
    /// Latched once the pointer has really travelled, so a click that wobbles
    /// leaves no undo step behind.
    var moved: Bool
}

extension CanvasNSView {

    // MARK: - What is showing

    /// The pivot on the canvas right now, with a drag in flight standing in
    /// for the stored value.
    ///
    /// Asked here rather than handed in by the one caller that knows about the
    /// drag, so that every other way the chrome gets refreshed while the
    /// button is down — an overlay pass, a scroll, a zoom, the preview's own
    /// thirty frames a second — draws the same live point.
    var showingMotionPivot: MotionPivotHandle? {
        guard tool == .select, let handle = motionPivot else { return nil }
        guard let drag = motionPivotDrag, drag.handle.motionID == handle.motionID else { return handle }
        return MotionPivotHandle(layerID: handle.layerID, motionID: handle.motionID,
                                 point: drag.current, box: handle.box)
    }

    /// How close a press has to land, in view points. The ring is 8 across, so
    /// this is a target a little larger than the thing you are aiming at,
    /// which is what every other handle on this canvas does.
    static let motionPivotGrabRadius: CGFloat = 11

    /// True where a press at `p` (document points) would take hold of the
    /// pivot. Shared by the press and by the pointer cue, so the cursor can
    /// never promise a grab the press does not make.
    func motionPivotHit(at p: CGPoint) -> MotionPivotHandle? {
        guard let viewport, let handle = showingMotionPivot else { return nil }
        let there = viewport.viewPoint(fromDocument: handle.point)
        let here = viewport.viewPoint(fromDocument: p)
        let reach = CanvasNSView.motionPivotGrabRadius
        return hypot(there.x - here.x, there.y - here.y) <= reach ? handle : nil
    }

    // MARK: - The chrome

    func setUpMotionPivotChrome() {
        motionPivotLayer.fillColor = nil
        motionPivotLayer.isHidden = true
        motionPivotLayer.lineWidth = 1.5
        motionPivotLayer.zPosition = 99
        motionPivotHaloLayer.fillColor = nil
        motionPivotHaloLayer.isHidden = true
        motionPivotHaloLayer.lineWidth = 3.5
        motionPivotHaloLayer.zPosition = 98
        motionPivotLabelLayer.isHidden = true
        motionPivotLabelLayer.zPosition = 99
        for shape in [motionPivotHaloLayer, motionPivotLayer] { layer?.addSublayer(shape) }
        layer?.addSublayer(motionPivotLabelLayer)
    }

    /// The crosshair in a ring, and the word for what it is.
    ///
    /// Drawn in view space, so it is the same size at every zoom: an icon is
    /// worked on at 800% and a handle that grew with it would cover the
    /// drawing it is supposed to sit on.
    ///
    /// It is drawn from the STORED layer, never the moving one, and that is
    /// the point: a rotation is the one thing that leaves its own pivot still,
    /// so while the bell swings the crosshair sits dead under it. A handle
    /// that swung with the picture would be a handle nobody could catch.
    func refreshMotionPivotChrome() {
        guard let viewport, let handle = showingMotionPivot else {
            for shape in [motionPivotLayer, motionPivotHaloLayer] {
                shape.isHidden = true
                shape.path = nil
            }
            motionPivotLabelLayer.isHidden = true
            return
        }
        let centre = viewport.viewPoint(fromDocument: handle.point)
        let ring: CGFloat = 8
        let arm: CGFloat = 12
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: centre.x - ring / 2, y: centre.y - ring / 2,
                                   width: ring, height: ring))
        path.move(to: CGPoint(x: centre.x - arm / 2, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x + arm / 2, y: centre.y))
        path.move(to: CGPoint(x: centre.x, y: centre.y - arm / 2))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + arm / 2))

        // A white rim UNDER the accent, because this sits on the drawing
        // itself rather than in the margin round it, and an icon is as often
        // black on white as white on black.
        motionPivotHaloLayer.path = path
        motionPivotHaloLayer.strokeColor = CGColor(gray: 1, alpha: 0.85)
        motionPivotHaloLayer.isHidden = false
        motionPivotLayer.path = path
        motionPivotLayer.strokeColor = NSColor.controlAccentColor.cgColor
        motionPivotLayer.isHidden = false

        // The word, because a crosshair on your own drawing is a thing you
        // have to be told the name of exactly once. It only ever shows while
        // that layer is picked, so it is never in the way of judging the icon.
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let size = ("pivot" as NSString).size(withAttributes: [.font: font])
        motionPivotLabelLayer.string = "pivot"
        motionPivotLabelLayer.font = font
        motionPivotLabelLayer.fontSize = font.pointSize
        motionPivotLabelLayer.foregroundColor = NSColor.controlAccentColor.cgColor
        motionPivotLabelLayer.contentsScale = window?.backingScaleFactor ?? 2
        motionPivotLabelLayer.frame = CGRect(x: (centre.x + arm / 2 + 3).rounded(),
                                             y: (centre.y + 1).rounded(),
                                             width: size.width.rounded(.up) + 2,
                                             height: size.height.rounded(.up))
        motionPivotLabelLayer.isHidden = false
    }

    // MARK: - The gesture

    /// A press with a pivot showing. True when the pivot took it, which stops
    /// the press from also picking the layer up or starting a marquee.
    func motionPivotMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard event.clickCount == 1, let handle = motionPivotHit(at: p) else { return false }
        motionPivotDrag = MotionPivotDrag(handle: handle, current: handle.point, moved: false)
        applyGrabCursor(.closedHand)
        // A pivot cannot be judged on a still picture: with the layer sitting
        // at nought degrees, moving what it turns around changes nothing you
        // can see. So grabbing the handle starts the loop, exactly as adding
        // the motion did, and the swing follows the hand.
        onMotionPivotBegin()
        refreshMotionPivotChrome()
        return true
    }

    /// The pointer, while the pivot is held. The picture follows it: this is
    /// the whole feature, and a preview that only caught up on release would
    /// make finding the mount a guessing game.
    func motionPivotMouseDragged(to p: CGPoint, event: NSEvent) {
        guard var drag = motionPivotDrag else { return }
        let start = drag.handle.point
        if !drag.moved, hypot(p.x - start.x, p.y - start.y) < 0.5 { return }
        drag.moved = true
        drag.current = p
        motionPivotDrag = drag
        onMotionPivotMove(p)
        refreshMotionPivotChrome()
    }

    /// The button up: one undo step for the whole drag, and none at all for a
    /// press that went nowhere.
    func motionPivotMouseUp() {
        // The release after Escape. The pivot went back where it was mounted
        // the moment the key was pressed, so all that is left is to forget
        // the gesture ever happened.
        if motionPivotCancelled {
            motionPivotCancelled = false
            applyGrabCursor(nil)
            return
        }
        guard let drag = motionPivotDrag else { return }
        motionPivotDrag = nil
        applyGrabCursor(nil)
        if drag.moved { onMotionPivotCommit() } else { onMotionPivotCancel() }
        refreshMotionPivotChrome()
    }
}
