import CoreGraphics
import Foundation

/// Magnetizes the ends of a drawn annotation — an arrow's tip, a line's tail, a
/// box's corner — to the UI boundaries already detected in the picture
/// (`EdgeMap`), to the pixel grid, and, underneath both, to the canvas grid.
///
/// The reason this exists is arithmetic: a Retina capture opens at half zoom, so
/// one step of the mouse moves the point TWO image pixels and landing on a
/// border by eye is luck. The caliper solved that long ago; an arrow that points
/// at the same border deserves the same magnet, drawn with the same yellow line.
///
/// What is different from a caliper foot is which axes may catch. A caliper leg
/// is gated by the direction the HAND is travelling. An arrow is gated by the
/// direction the ARROW is pointing, which is steadier and closer to what the
/// user means: an arrow lying flat is pointing at a vertical border, so its tip
/// takes that border's x and keeps the height you chose along it; a diagonal
/// arrow is pointing into a corner and takes both. Box shapes always take both,
/// because a corner is a corner.
///
/// The canvas grid comes in underneath all of that, as a quantize rather than a
/// magnet, exactly as it does for a move or a resize: whatever no real edge
/// caught lands on the nearest line of the grid you can see. So a grid never
/// stops a mark matching a real border, and away from real borders a shape you
/// draw starts and ends on the graph paper rather than near it.
public enum AnnotationSnapping {

    /// How square-on a line has to be before its cross axis stops catching:
    /// within about 17 degrees of an axis the shaft reads as pointing straight
    /// along it. Anything more oblique is aimed at a corner and takes both.
    public static let axisPurityRatio: CGFloat = 0.3

    /// The axes this endpoint may catch edges on. `opposite` is the end that is
    /// staying put (nil while the first point is still being placed).
    public static func axes(shape: AnnotationShape, opposite: CGPoint?,
                            moving: CGPoint) -> (x: Bool, y: Bool) {
        guard shape == .line || shape == .arrow, let opposite else { return (true, true) }
        let dx = abs(moving.x - opposite.x)
        let dy = abs(moving.y - opposite.y)
        guard dx > 0 || dy > 0 else { return (true, true) }
        if dy < dx * axisPurityRatio { return (x: true, y: false) }
        if dx < dy * axisPurityRatio { return (x: false, y: true) }
        return (true, true)
    }

    /// How far the pointer has to have travelled from the end that is staying
    /// put before the draw counts as a drag rather than a click, in screen
    /// points. The same four `AnnotationDrag.isClick` uses, because it answers
    /// the same question: below it there is no shape yet, so there is nothing
    /// for the grid to give a minimum size to.
    public static let dragThreshold: CGFloat = 4

    /// Snaps one end of an annotation being drawn or re-shaped.
    /// - point: where the pointer is, in document coordinates.
    /// - shape: what is being drawn (decides the axis gate above). Nil for the
    ///   two tools that drag out a plain box and carry no annotation shape, the
    ///   frame tool and the zoom callout. They take no edge magnets (they never
    ///   had any) but they are boxes, so they land on the grid like one.
    /// - opposite: the end staying put, or nil when there is not one yet.
    /// - free: the user refused the magnet (⌘, or a constrained ⇧ drag whose
    ///   angle owns the point); the pointer position is returned untouched.
    /// - holding: the EDGES this drag is already standing on, so a caught edge
    ///   is not taken and given back under a wobbling hand.
    /// - gridHolding: the same memory for grid lines, and deliberately a
    ///   separate one. A held line is handed straight back as a guide, so a
    ///   grid line dropped into the edge memory would come back out claiming to
    ///   be a border found in the picture: the yellow guide would light for a
    ///   grid line, and the grid's own quantize would never get a turn.
    /// - gridSpacing: how far apart the canvas grid's lines are, or nil when
    ///   nothing is pulling (grid off, Snap to grid off, feature off).
    /// - gridOrigin: where the grid starts counting, so a snapped end sits ON a
    ///   drawn line rather than beside it.
    /// - gridAxes: a grid set to columns draws nothing across, so the other
    ///   axis has no line to land on.
    public static func snap(_ point: CGPoint, shape: AnnotationShape?,
                            opposite: CGPoint?, edges: EdgeMap, zoom: CGFloat,
                            free: Bool = false,
                            screenTolerance: CGFloat = 8,
                            holding: SnapHold = .none,
                            gridHolding: SnapHold = .none,
                            gridSpacing: CGFloat? = nil,
                            gridOrigin: CGPoint = .zero,
                            gridAxes: CanvasGridAxes = .columnsAndRows) -> EdgeSnapping.Snap {
        guard !free else { return EdgeSnapping.Snap(point: point) }
        guard let shape else {
            // A frame or a zoom callout: a plain box, no edge magnets, but the
            // grid holds it exactly as it holds a rectangle.
            return onGrid(EdgeSnapping.Snap(point: point), pointer: point, opposite: opposite,
                          allowed: (true, true), zoom: zoom, screenTolerance: screenTolerance,
                          holding: gridHolding, spacing: gridSpacing, origin: gridOrigin,
                          axes: gridAxes)
        }
        // What this pointer would catch on its own, with no memory of the drag.
        var snap = EdgeSnapping.snap(point, edges: edges, zoom: zoom,
                                     screenTolerance: screenTolerance,
                                     includeCenters: false, snapToPixelGrid: true)
        // …then the drag's memory, but only where it is still the best answer.
        //
        // A caught line keeps a drag until the pointer is clearly away from it,
        // which is what stops a wobbling hand taking a line and giving it back.
        // A mark being DRAWN sweeps right across the picture to reach what it
        // points at, though, and crossing a line is not catching one: a text
        // baseline picked up on the way would ride along for the rest of the
        // sweep and park the tip a dozen points short of the border you aimed
        // at — the very complaint this exists to answer. So a held line that is
        // farther from the pointer than a line the pointer can reach by itself
        // is treated as left behind rather than held.
        var kept = holding
        if let x = kept.x, let fresh = snap.guideX, abs(x - point.x) > abs(fresh - point.x) {
            kept.x = nil
        }
        if let y = kept.y, let fresh = snap.guideY, abs(y - point.y) > abs(fresh - point.y) {
            kept.y = nil
        }
        if kept.x != nil || kept.y != nil {
            snap = EdgeSnapping.snap(point, edges: edges, zoom: zoom,
                                     screenTolerance: screenTolerance,
                                     includeCenters: false, snapToPixelGrid: true,
                                     holding: kept)
        }
        let allowed = axes(shape: shape, opposite: opposite, moving: point)
        if !allowed.x {
            snap.point.x = point.x.rounded()
            snap.guideX = nil
        }
        if !allowed.y {
            snap.point.y = point.y.rounded()
            snap.guideY = nil
        }
        return onGrid(snap, pointer: point, opposite: opposite, allowed: allowed,
                      zoom: zoom, screenTolerance: screenTolerance, holding: gridHolding,
                      spacing: gridSpacing, origin: gridOrigin, axes: gridAxes)
    }

    /// Puts whatever no real edge caught onto the nearest line of the canvas
    /// grid, and stops a drawn shape collapsing to nothing on the way.
    ///
    /// The grid runs on BOTH axes whatever the edge gate said, because the gate
    /// answers a different question. It is there so a level arrow cannot grab
    /// some unrelated horizontal border on its way past; a grid line is never
    /// unrelated, it is one of the lines the whole picture is being built on,
    /// and an arrow drawn nearly level across graph paper coming out exactly
    /// level is the point rather than a surprise.
    ///
    /// The floor is the other half. The grid quantizes with no tolerance, so a
    /// drag shorter than half a cell would put both ends of the shape on the
    /// same line: a box with no width, and once both axes collapse, a drag the
    /// commit reads as a click and draws nothing at all. Dragging and getting
    /// no shape is the one outcome a person blames the tool for. So once the
    /// pointer has clearly moved, each axis the shape may catch on gets at
    /// least one whole cell, in the direction the hand went. On graph paper the
    /// smallest thing you can draw is one square, which is what graph paper has
    /// always meant, and ⌘ still draws any size at all.
    private static func onGrid(_ snap: EdgeSnapping.Snap, pointer: CGPoint,
                               opposite: CGPoint?, allowed: (x: Bool, y: Bool),
                               zoom: CGFloat, screenTolerance: CGFloat,
                               holding: SnapHold, spacing: CGFloat?,
                               origin: CGPoint, axes: CanvasGridAxes) -> EdgeSnapping.Snap {
        guard let spacing, spacing.isFinite, spacing > 0 else { return snap }
        var snap = snap
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance

        if snap.guideX == nil {
            let landed = Snapping.quantized(snap.point.x, to: spacing, from: origin.x,
                                            held: holding.x, tolerance: tolerance)
            snap.point.x = landed
            snap.gridX = landed
        }
        // Columns only: nothing is drawn across the canvas, so there is no line
        // across to land on and the vertical stays where the hand put it.
        if snap.guideY == nil, axes.drawsRows {
            let landed = Snapping.quantized(snap.point.y, to: spacing, from: origin.y,
                                            held: holding.y, tolerance: tolerance)
            snap.point.y = landed
            snap.gridY = landed
        }

        // Far enough from the fixed end to be a drag: below this the shape does
        // not exist yet and a floor would turn a click into a whole cell.
        guard let opposite,
              hypot(pointer.x - opposite.x, pointer.y - opposite.y) * zoom >= dragThreshold
        else { return snap }
        if allowed.x, snap.gridX != nil, snap.point.x == opposite.x, pointer.x != opposite.x {
            snap.point.x += pointer.x > opposite.x ? spacing : -spacing
            snap.gridX = snap.point.x
        }
        if allowed.y, snap.gridY != nil, snap.point.y == opposite.y, pointer.y != opposite.y {
            snap.point.y += pointer.y > opposite.y ? spacing : -spacing
            snap.gridY = snap.point.y
        }
        return snap
    }
}
