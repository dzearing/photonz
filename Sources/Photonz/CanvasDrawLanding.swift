import AppKit
import PhotonzCore
import SwiftUI

// Where the first point will land, marked before you press it.
//
// Every tool that starts a shape is magnetic: with the grid on a point goes to
// the nearest crossing, and near a border found in the picture it goes to that
// border. Until now none of that showed until after the click, so placing a
// point was a press followed by finding out, and the way to correct it was
// undo. This draws the answer under the pointer while you are still aiming.
//
// The rule it follows is that there is exactly ONE place that decides where a
// point goes. The mark asks the same snap the press asks — `PenSession.landing`
// for the Pen, `AnnotationSnapping.snap` for everything that drags a shape out
// — rather than working the landing out a second way. A mark computed
// separately would eventually disagree with the press, and a mark that lies is
// worse than no mark.
//
// It is drawn whenever a LINE places the point rather than the hand, which is a
// grid crossing, a guide somebody pinned, or a border found in the picture
// (`EdgeSnapping.Snap.isPlaced`). The picture's own borders were left out at
// first on a cost worry, and the worry turned out to be a measurement of an
// unoptimized build: in the build that ships, one hover frame over a 2560 by
// 1600 screenshot costs about 17 microseconds. See `DrawLandingCostTests`.

extension CanvasNSView {

    // MARK: The mark

    /// The ring the mark is drawn as, and how it is drawn.
    ///
    /// It is the measure tool's hover snap dot (`snapDotLayer`) with its middle
    /// taken out: the same system accent, the same white edge that keeps it
    /// readable over a photograph, at the same place in the stack. Open rather
    /// than filled because this one sits ON the crossing it is pointing at, and
    /// a filled dot would hide the very line it is claiming.
    enum DrawLandingMark {
        /// Radius of the accent ring, in screen points, so it is the same size
        /// at every zoom.
        static let radius: CGFloat = 5
        /// The white hairline just outside it, so the ring reads on a dark
        /// canvas and over a busy screenshot alike.
        static let edge: CGFloat = 6.25
    }

    func setUpDrawLandingChrome() {
        drawLandingLayer.fillColor = nil
        drawLandingLayer.strokeColor = NSColor.controlAccentColor.cgColor
        drawLandingLayer.lineWidth = 1.5
        drawLandingLayer.isHidden = true
        drawLandingLayer.zPosition = 100
        drawLandingEdgeLayer.fillColor = nil
        drawLandingEdgeLayer.strokeColor = CGColor(gray: 1, alpha: 0.9)
        drawLandingEdgeLayer.lineWidth = 1
        drawLandingEdgeLayer.isHidden = true
        drawLandingEdgeLayer.zPosition = 99.5
        layer?.addSublayer(drawLandingEdgeLayer)
        layer?.addSublayer(drawLandingLayer)
    }

    // MARK: What the press would do

    /// Whether this tool starts a shape with its first press, which is the set
    /// of tools the mark is for. It MIRRORS the branch in `mouseDown` that
    /// begins a draw, so a tool that draws is a tool that aims.
    var toolStartsAShape: Bool {
        tool == .pen || tool.createsAnnotationByDrag || tool == .zoomCallout
            || tool == .frame || tool == .lens
    }

    /// Where a press right now would put the first point, in document space,
    /// or nil when there is nothing worth marking.
    ///
    /// Nothing worth marking means one of four things, and each of them is an
    /// honest answer rather than a gap:
    ///
    /// - The tool does not start a shape, or a button is already down. There is
    ///   no press to aim.
    /// - ⌘ is held. The point lands exactly under the pointer, which is what ⌘
    ///   means everywhere on this canvas, and the cursor is already sitting
    ///   there saying so.
    /// - No line would place the point: no grid pulling, no guide pinned near,
    ///   and no border found in the picture within reach. A press then lands
    ///   under the pointer, and a ring that followed the cursor around saying
    ///   "here" would be chrome that never carries news. That test is
    ///   `EdgeSnapping.Snap.isPlaced`, asked of the very snap the press will
    ///   ask.
    /// - The Pen is aimed at an anchor it already drew, to close or finish the
    ///   path. `penTargetLayer` rings that anchor already, and two rings on one
    ///   point is not clearer than one.
    var drawLanding: CGPoint? {
        guard Experiments.shared.drawLandingEnabled, toolStartsAShape, let viewport,
              let hoverPoint, bounds.contains(hoverPoint),
              annotationDrag == nil, endpointDrag == nil, moveDrag == nil,
              resizeDrag == nil, !penSession.isPressing
        else { return nil }
        let free = pointerModifiers.contains(.command)
        guard !free else { return nil }
        let pointer = viewport.documentPoint(fromView: hoverPoint)
        if tool == .pen {
            // The Pen is the one drawing tool with no border magnets at all:
            // `PenSession.landing` knows the grid, the 45 degree constraint and
            // its own anchors, and nothing about the picture underneath. So it
            // has something to aim at exactly when the grid is pulling.
            guard canvasSnapSpacing != nil else { return nil }
            let aim = penSession.landing(at: pointer,
                                         constrained: pointerModifiers.contains(.shift),
                                         breaking: pointerModifiers.contains(.option),
                                         zoom: viewport.zoom)
            guard !aim.isOnAnExistingAnchor else { return nil }
            return aim.point
        }
        // The same question the press asks, with the same memory the press
        // starts with: `mouseDown` calls `resetDrawSnapMemory()` before it
        // snaps, so a draw opens standing on nothing and the hover has to ask
        // standing on nothing too.
        let snap = AnnotationSnapping.snap(pointer, shape: tool.annotationShape,
                                           opposite: nil, edges: edgeMap,
                                           zoom: viewport.zoom, free: false,
                                           holding: .none, gridHolding: .none,
                                           gridSpacing: canvasSnapSpacing,
                                           gridOrigin: canvasSnapOrigin,
                                           gridAxes: canvasSnapAxes,
                                           guides: canvasSnapGuides)
        // A line has to have placed the point for there to be news: a grid
        // crossing, a pinned guide, or a border found in the picture. On a
        // plain screenshot with nothing in reach the press lands under the
        // pointer, and the ring stays away rather than sitting there saying
        // nothing.
        guard snap.isPlaced else { return nil }
        // The mark stays even when the pointer is already dead on a crossing:
        // "you are on the line" is the answer, and a mark that blinked out
        // exactly when you got it right would be maddening.
        return snap.point
    }

    /// The point marked on screen RIGHT NOW, for a scripted walk to read: the
    /// document point the ring is drawn on, or nil when no ring is showing.
    var liveDrawLanding: CGPoint? { drawLandingShown }

    // MARK: Drawing it

    /// Puts the ring where a press would land, or takes it away. Cheap enough
    /// to call on every mouse move: one snap query and two ellipse paths.
    func refreshDrawLanding() {
        guard let viewport, let landed = drawLanding else {
            hideDrawLanding()
            return
        }
        let v = viewport.viewPoint(fromDocument: landed)
        func ring(_ r: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: r * 2, height: r * 2),
                   transform: nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawLandingLayer.path = ring(DrawLandingMark.radius)
        drawLandingLayer.isHidden = false
        drawLandingEdgeLayer.path = ring(DrawLandingMark.edge)
        drawLandingEdgeLayer.isHidden = false
        CATransaction.commit()
        drawLandingShown = landed
    }

    func hideDrawLanding() {
        guard drawLandingShown != nil || !drawLandingLayer.isHidden else { return }
        drawLandingLayer.isHidden = true
        drawLandingLayer.path = nil
        drawLandingEdgeLayer.isHidden = true
        drawLandingEdgeLayer.path = nil
        drawLandingShown = nil
    }
}
