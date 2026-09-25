import AppKit
import PhotonzCore
import SwiftUI

// The path a moving layer travels, on the canvas (task
// `a-moving-layer-draws-its-path-on-the-canvas-and`,
// `docs/design/mocks/pages/video-move-wt.html` steps 5, 7 and 8).
//
// Once a layer is keyed at two places, the picked layer shows the route it
// will travel as a dashed line: the same two numbers the Position lane shows,
// seen in space rather than in time. A circle sits on each key, and a small
// square sits on the middle of each stretch. Dragging the square bends that
// stretch into an arc through wherever it is let go; a double-click on it puts
// the stretch back on its line.
//
// Everything that decides WHERE the path runs lives in `MotionPath.swift`
// (PhotonzCore) and is tested there. This file draws, and hands one finished
// bend to the editor, exactly as the pivot crosshair does
// (`CanvasMotionPivot.swift`).

/// The handle under the hand.
struct MotionPathDrag {
    let layerID: UUID
    let segment: Int
    /// Where the handle was when it was taken hold of, in document points.
    let start: CGPoint
    /// Latched once the pointer has really travelled, so a click that wobbles
    /// leaves no undo step behind.
    var moved: Bool
}

extension CanvasNSView {

    /// How close a press has to land to the square, in view points: a target
    /// a little larger than the six point square itself, like every other
    /// handle here.
    static let motionPathGrabRadius: CGFloat = 9

    /// The stretch whose handle a press at `p` (document points) would take
    /// hold of. Shared by the press and the pointer cue, so the cursor can
    /// never promise a grab the press does not make.
    func motionPathHandleHit(at p: CGPoint) -> (layerID: UUID, segment: Int, point: CGPoint)? {
        guard tool == .select, let viewport, let path = motionPath else { return nil }
        let here = viewport.viewPoint(fromDocument: p)
        var best: (Int, CGPoint, CGFloat)?
        for (index, run) in path.segments.enumerated() {
            let there = viewport.viewPoint(fromDocument: run.middle)
            let distance = hypot(there.x - here.x, there.y - here.y)
            guard distance <= CanvasNSView.motionPathGrabRadius else { continue }
            if best == nil || distance < (best?.2 ?? .infinity) { best = (index, run.middle, distance) }
        }
        return best.map { (path.layerID, $0.0, $0.1) }
    }

    // MARK: - The chrome

    func setUpMotionPathChrome() {
        motionPathLineLayer.fillColor = nil
        motionPathLineLayer.lineWidth = 1.25
        motionPathLineLayer.lineDashPattern = [4, 4]
        motionPathLineLayer.isHidden = true
        motionPathLineLayer.zPosition = 97
        motionPathHaloLayer.fillColor = nil
        motionPathHaloLayer.lineWidth = 3
        motionPathHaloLayer.isHidden = true
        motionPathHaloLayer.zPosition = 96
        motionPathKeysLayer.lineWidth = 1.25
        motionPathKeysLayer.isHidden = true
        motionPathKeysLayer.zPosition = 98
        motionPathHandlesLayer.lineWidth = 1
        motionPathHandlesLayer.isHidden = true
        motionPathHandlesLayer.zPosition = 98
        for shape in [motionPathHaloLayer, motionPathLineLayer, motionPathKeysLayer, motionPathHandlesLayer] {
            layer?.addSublayer(shape)
        }
    }

    /// The dashed route, a ring on every key and a square on the middle of
    /// every stretch. Drawn in view space so it is the same weight at every
    /// zoom, and only while the moving layer is the one picked.
    func refreshMotionPathChrome() {
        let shapes = [motionPathLineLayer, motionPathHaloLayer, motionPathKeysLayer, motionPathHandlesLayer]
        guard tool == .select, let viewport, let path = motionPath, !isMotionPathHiddenForDrag else {
            for shape in shapes {
                shape.isHidden = true
                shape.path = nil
            }
            return
        }
        let accent = NSColor.controlAccentColor.cgColor
        let line = CGMutablePath()
        for run in path.segments {
            let start = viewport.viewPoint(fromDocument: run.start)
            let end = viewport.viewPoint(fromDocument: run.end)
            line.move(to: start)
            if run.isCurved {
                line.addQuadCurve(to: end, control: viewport.viewPoint(fromDocument: run.control))
            } else {
                line.addLine(to: end)
            }
        }
        // A soft dark rim under the dashes, because the route crosses the
        // picture itself and a recording is as often white as it is dark.
        motionPathHaloLayer.path = line
        motionPathHaloLayer.strokeColor = CGColor(gray: 0, alpha: 0.28)
        motionPathLineLayer.path = line
        motionPathLineLayer.strokeColor = accent

        let ring: CGFloat = 7
        let keys = CGMutablePath()
        for point in path.keyPoints {
            let centre = viewport.viewPoint(fromDocument: point)
            keys.addEllipse(in: CGRect(x: centre.x - ring / 2, y: centre.y - ring / 2, width: ring, height: ring))
        }
        motionPathKeysLayer.path = keys
        motionPathKeysLayer.fillColor = NSColor.windowBackgroundColor.cgColor
        motionPathKeysLayer.strokeColor = accent

        let square: CGFloat = 7
        let handles = CGMutablePath()
        for run in path.segments {
            let centre = viewport.viewPoint(fromDocument: run.middle)
            handles.addRoundedRect(in: CGRect(x: centre.x - square / 2, y: centre.y - square / 2,
                                              width: square, height: square),
                                   cornerWidth: 1.5, cornerHeight: 1.5)
        }
        motionPathHandlesLayer.path = handles
        motionPathHandlesLayer.fillColor = accent
        motionPathHandlesLayer.strokeColor = CGColor(gray: 1, alpha: 0.9)
        for shape in shapes { shape.isHidden = false }
    }

    /// The route is about where the layer goes; while the layer ITSELF is
    /// being dragged the route it had is old news, and drawing it would show
    /// a line to a key that is about to move.
    var isMotionPathHiddenForDrag: Bool { dragPreview != nil }

    // MARK: - The gesture

    /// A press with a path showing. True when a handle took it, which stops
    /// the press from also picking up the layer underneath.
    func motionPathMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard let hit = motionPathHandleHit(at: p) else { return false }
        if event.clickCount == 2 {
            motionPathDrag = nil
            onMotionPathStraighten(hit.layerID, hit.segment)
            return true
        }
        guard event.clickCount == 1 else { return true }
        motionPathDrag = MotionPathDrag(layerID: hit.layerID, segment: hit.segment, start: hit.point, moved: false)
        applyGrabCursor(.closedHand)
        return true
    }

    /// The pointer, while a handle is held: the arc and the layer follow it.
    func motionPathMouseDragged(to p: CGPoint) {
        guard var drag = motionPathDrag else { return }
        if !drag.moved, hypot(p.x - drag.start.x, p.y - drag.start.y) < 0.5 { return }
        drag.moved = true
        motionPathDrag = drag
        onMotionPathBendPreview(drag.layerID, drag.segment, p)
    }

    /// The button up: one undo step for the whole bend, none for a press
    /// that went nowhere.
    func motionPathMouseUp() {
        guard let drag = motionPathDrag else { return }
        motionPathDrag = nil
        applyGrabCursor(nil)
        if drag.moved { onMotionPathBendCommit() } else { onMotionPathBendCancel() }
    }

    /// Escape with a handle in hand: the path goes back where it was.
    func motionPathEscape() -> Bool {
        guard motionPathDrag != nil else { return false }
        motionPathDrag = nil
        applyGrabCursor(nil)
        onMotionPathBendCancel()
        return true
    }
}
