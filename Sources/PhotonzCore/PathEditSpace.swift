import CoreGraphics
import Foundation

// Reshaping a path that has been TURNED (Next, `next-reshape-a-path`).
//
// A path on a slant used to show no points at all, and the refusal was honest
// about why: reshaping moves the box the shape sits in, a turn is measured
// about the middle of that box, so growing the box moves the pivot and takes
// the drawing with it.
//
// Working it out says the drawing does not SWING, it SLIDES. For a turn whose
// linear part is L, about a pivot that moves from c0 to c1, every point of the
// shape lands (I - L)·(c1 - c0) away from where it was: the same amount
// whichever point you ask about, because the shape's own coordinates and the
// box's corner move together. One offset puts all of it back, which is the
// same trick a resize on a turned layer already plays (`Handles.anchoredFrame`).
//
// So the three things a turned path needs are all here, in one value taken at
// the press and held for the whole gesture: the map that takes a press into
// the shape's own coordinates, the map back out for drawing the points on it,
// and the box a reshaped turned path has to take so the parts nobody touched
// do not move.

/// Where a layer's own coordinates sit in the document: the corner its shape
/// is measured from, the turn on it, and what that turn is about.
///
/// Held as a value rather than re-read from the layer each frame, because the
/// box moves as a shape grows past its old edges and a drag that re-read the
/// map every frame would chase its own tail. Same bargain
/// `PathAnchorDrag.original` already makes with the shape itself.
public struct PathEditSpace: Hashable, Sendable {

    /// The layer's box, in the document. Its corner is the origin of the
    /// shape's own coordinates.
    public let frame: CGRect
    public let transform: LayerTransform
    /// What the turn is about, where the layer has been told, and nil for the
    /// middle of the box, which is what everything did before pivots existed.
    public let pivot: MotionPivot?
    /// How the CARDS above this layer have turned it
    /// (`PhotonzDocument.inheritedTurn`). A layer's own numbers are stated in
    /// the upright space inside its card, so a piece of a card on a slant needs
    /// the card's swing taking off the press and putting back on the drawing.
    /// Identity for everything at the top level.
    public let inheritedTurn: CGAffineTransform

    public init(frame: CGRect, transform: LayerTransform, pivot: MotionPivot?,
                inheritedTurn: CGAffineTransform = .identity) {
        self.frame = frame
        self.transform = transform
        self.pivot = pivot
        self.inheritedTurn = inheritedTurn
    }

    /// The space a layer's own path is stated in.
    public init(layer: Layer, inheritedTurn: CGAffineTransform = .identity) {
        self.init(frame: layer.frame, transform: layer.transform, pivot: layer.motionPivot,
                  inheritedTurn: inheritedTurn)
    }

    /// The point the turn is about, in the document.
    public var turnPoint: CGPoint {
        if let pivot { return pivot.point(in: frame) }
        let box = frame.standardized
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// The map from the shape's own coordinates out into the document.
    public var outward: CGAffineTransform {
        var out = CGAffineTransform(translationX: frame.minX, y: frame.minY)
        if !transform.isIdentity {
            out = out.concatenating(transform.affineTransform(around: turnPoint))
        }
        if !inheritedTurn.isIdentity { out = out.concatenating(inheritedTurn) }
        return out
    }

    /// The map the other way, which is what a press goes through.
    public var inward: CGAffineTransform {
        guard !transform.isIdentity || !inheritedTurn.isIdentity else {
            return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
        }
        return outward.inverted()
    }

    /// A point of the shape's own coordinates, on the canvas.
    public func document(_ p: CGPoint) -> CGPoint { p.applying(outward) }

    /// A press on the canvas, in the shape's own coordinates.
    public func local(_ p: CGPoint) -> CGPoint { p.applying(inward) }

    /// A direction on SCREEN said in the shape's own coordinates: what an
    /// arrow key means to a point on a turned shape.
    ///
    /// A nudge is a push the way the key points, not a push along the shape's
    /// own grain: pressing the up arrow on a point of a shape turned thirty
    /// degrees has to move it up the canvas, or the key does not mean what it
    /// says. Only the linear part of the map counts, since a direction has
    /// nothing to say about where the box sits.
    public func localVector(_ d: CGPoint) -> CGPoint {
        guard !transform.isIdentity || !inheritedTurn.isIdentity else { return d }
        let t = inward
        return CGPoint(x: d.x * t.a + d.y * t.c, y: d.x * t.b + d.y * t.d)
    }

    /// The box a reshaped shape takes, placed so a point nobody moved does not
    /// move: `contentBounds` is the box the shape's points now make, in THESE
    /// coordinates.
    ///
    /// Straight on, that is the old corner plus the new box, which is what it
    /// has always been. Turned, the box is then pushed back by exactly as far
    /// as moving the pivot slid the drawing, worked out by asking one point
    /// that did not move — the corner the shape's own coordinates are measured
    /// from — where it lands before and after.
    public func steadyFrame(contentBounds: CGRect) -> CGRect {
        let box = contentBounds.standardized
        let naive = CGRect(x: frame.minX + box.minX, y: frame.minY + box.minY,
                           width: box.width, height: box.height)
        // The card's own swing has nothing to say here: it is applied AFTER
        // this box is placed, and it is `holdingTurnedPivots` that keeps a card
        // still while a piece inside it changes.
        guard !transform.isIdentity else { return naive }
        let moved = PathEditSpace(frame: naive, transform: transform, pivot: pivot)
        let before = frame.origin.applying(transform.affineTransform(around: turnPoint))
        let after = frame.origin.applying(transform.affineTransform(around: moved.turnPoint))
        return naive.offsetBy(dx: before.x - after.x, dy: before.y - after.y)
    }
}
