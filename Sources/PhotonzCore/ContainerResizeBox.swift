import CoreGraphics
import Foundation

/// The box the canvas outlines while a container's handle is being dragged.
///
/// Most things show their own resize. A rectangle stretches, a plain group
/// multiplies everything inside it by the amount its box changed by, a copy of
/// a component places its pieces in the box it is given: pull a handle on any
/// of those and the picture under your hand is already saying what you are
/// getting. A screen says it with the hairline at its own edge, which follows
/// the drag (`CanvasFrames.liveCanvasBounds`).
///
/// A group that ARRANGES itself says nothing. Its rows sit where its own rules
/// put them — a left aligned column keeps every row at its own width against
/// the left edge however wide the stack gets — and a group has no edge of its
/// own to follow. So a drag on one changed nothing at all on screen: reported
/// on 2026-09-09, with the rows still exactly where they had been at the end of
/// the travel and only the number in the panel moving.
///
/// What it gets instead is the box itself, drawn for as long as the button is
/// down. The rule for WHICH box is the point of this file: it is the box the
/// drag will LAND in, not the one the pointer is over. A stack told the widest
/// it may ever be stops there, and the outline has to stop there with it, or
/// the drag would promise a shape the release does not give.
public enum ContainerResizeBox {

    /// The box to outline while `layer` is being dragged to `dragged`, or nil
    /// for everything that already shows its own resize.
    ///
    /// `dragged` and the answer are in the same space, whichever that is: the
    /// canvas hands this a box in canvas coordinates and gets one back, because
    /// nothing here moves the box's origin, it only decides its size.
    public static func box(of layer: Layer, draggedTo dragged: CGRect) -> CGRect? {
        guard needsOne(layer) else { return nil }
        // Through the same door the release goes through, so the outline and
        // the landing can never disagree: whatever the flow does with a box
        // this size — hold it at a limit it was given, keep it smaller than the
        // rows inside it — is what gets drawn. It costs one flow of one group
        // per pointer move, next to the composite the same move already asks
        // for.
        return layer.resized(to: dragged).localBounds
    }

    /// Whether this layer is one of the containers that shows nothing while it
    /// is resized.
    private static func needsOne(_ layer: Layer) -> Bool {
        guard let group = layer.group else { return false }
        // A screen's own edge is already live, and drawing a second line on top
        // of it would be two boxes claiming one edge.
        guard !group.isFrame else { return false }
        // A copy of a component is told its size and lays its pieces out in it,
        // so the picture moves under the hand.
        guard group.instanceOf == nil else { return false }
        // A group that arranges nothing scales what is inside it, and what is
        // inside it IS its box.
        return group.layout?.arranges == true
    }
}
