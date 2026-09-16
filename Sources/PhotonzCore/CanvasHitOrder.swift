import CoreGraphics
import Foundation

/// One written answer to "what does a press over overlapping canvas chrome
/// take hold of".
///
/// A picked layer wears several marks at once — eight resize squares, four
/// rounding dots, a turn knob floated off the top edge, and, once it turns, a
/// crosshair for the point it turns around. Most of the time they are yards
/// apart and the question never comes up. Where two of them land on the same
/// few points, something has to decide, and until now every overlap was
/// settled by hand, by moving one hit test above another in a long list. Two
/// of those hand-rolled answers went the wrong way within two days of each
/// other: a pivot parked near a corner could not be picked up at all, and a
/// path's points said one thing under the pointer and did another under the
/// press.
///
/// So the rule is written down once, here, and it is the one every list in
/// that file already used inside itself: **the nearest drawn mark takes the
/// press**, and a mark drawn ON the picture wins a tie against the box drawn
/// round it. A mark only ever competes where it is actually in reach: chrome
/// the press was going to miss anyway never takes a press away from chrome it
/// would have hit.
///
/// The prose version, with the bands a press is read in and the cases it
/// settles, is `docs/design/canvas-hit-order.md`.
public enum CanvasHitOrder {

    /// How near the press at `p` is to the nearest mark the picked layer's own
    /// BOX draws that would take it — the turn knob, a rounding dot, a resize
    /// square, or the live stretch of an edge — or nil where the box would
    /// take this press nowhere.
    ///
    /// Everything is stated in the layer's own upright space, which is where
    /// its handles are hit-tested (`CanvasPointer.handleSpacePoint`), so a
    /// turned layer answers where its chrome draws. `frame` nil means no frame
    /// handles were offered, so none competes; `knob` nil means no turn knob;
    /// `roundingDots` is the same question the press asks before reading them.
    public static func boxGrabDistance(at p: CGPoint, frame: CGRect?, zoom: CGFloat,
                                       knob: CGPoint? = nil,
                                       roundingDots: Bool = false,
                                       radii: CornerRadii = .none,
                                       edgeGrab: Bool = false) -> CGFloat? {
        let z = zoom > 0 ? zoom : 1
        var nearest: CGFloat?
        func offer(_ distance: CGFloat, within slack: CGFloat) {
            guard distance <= slack / z, distance < (nearest ?? .infinity) else { return }
            nearest = distance
        }
        if let knob {
            offer(hypot(p.x - knob.x, p.y - knob.y), within: CanvasPointer.rotateTolerance)
        }
        guard let frame else { return nearest }
        if roundingDots, let dot = CornerRadiusHandles.grab(at: p, frame: frame, radii: radii,
                                                            zoom: zoom) {
            offer(dot.distance, within: CornerRadiusHandles.tolerance)
        }
        if let handle = Handles.grab(at: p, frame: frame, zoom: zoom, edgeGrab: edgeGrab) {
            offer(handle.distance, within: Handles.tolerance)
        }
        return nearest
    }

    /// Whether a press at `p` belongs to the mark drawn at `mark` rather than
    /// to the picked layer's own box chrome.
    ///
    /// The mark wins where it is nearer, and it wins a tie: a crosshair parked
    /// exactly on a corner is a crosshair somebody put there on purpose, and
    /// it is the one of the two with no other way in — a resize can be pulled
    /// from any of the other seven handles or typed into Position & Size.
    ///
    /// It does NOT ask whether the press is within the mark's own reach. That
    /// is the caller's question, because every mark carries its own, and this
    /// only settles the argument between two marks that are both in reach.
    public static func markTakesPress(at p: CGPoint, mark: CGPoint, frame: CGRect?,
                                      zoom: CGFloat, knob: CGPoint? = nil,
                                      roundingDots: Bool = false,
                                      radii: CornerRadii = .none,
                                      edgeGrab: Bool = false) -> Bool {
        guard let box = boxGrabDistance(at: p, frame: frame, zoom: zoom, knob: knob,
                                        roundingDots: roundingDots, radii: radii,
                                        edgeGrab: edgeGrab) else { return true }
        return hypot(p.x - mark.x, p.y - mark.y) <= box
    }
}
