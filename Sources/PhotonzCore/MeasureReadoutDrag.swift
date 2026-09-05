import CoreGraphics
import Foundation

/// Dragging a measurement's number around: the pure geometry behind taking hold
/// of the readout pill and putting it somewhere else.
///
/// The pill moves in two directions and they mean different things.
///
/// * ACROSS the measuring line the pill carries the caliper's head with it, so
///   the fork gets deeper or shallower and the number stays on its bar. That is
///   `headOffset`, and it is the only direction the readout used to move.
/// * ALONG the measuring line only the number moves. The feet, the fork and the
///   measured value are untouched — the number just slides left and right on
///   its own bar. That is `labelNudge`, which the automatic placer already uses
///   to keep two nearby numbers from stacking.
///
/// Both directions line up with the readouts already on the picture, which is
/// the point: a stack of width measurements can be pulled into one tidy column
/// of numbers even though every span has a different midpoint.
public enum MeasureReadoutDrag {

    /// Where a drag wants the caliper: the two numbers to write, plus the lines
    /// (document space) the pill actually landed on, for drawing the guide.
    public struct Placement: Equatable, Sendable {
        public var headOffset: CGFloat
        public var labelNudge: CGFloat
        /// The x line the pill snapped to, if any.
        public var guideX: CGFloat?
        /// The y line the pill snapped to, if any.
        public var guideY: CGFloat?

        public init(headOffset: CGFloat, labelNudge: CGFloat,
                    guideX: CGFloat? = nil, guideY: CGFloat? = nil) {
            self.headOffset = headOffset
            self.labelNudge = labelNudge
            self.guideX = guideX
            self.guideY = guideY
        }

        /// Where the number ended up along its line, and whether that counts as
        /// hand-placed.
        ///
        /// A number sitting exactly on its own centre does not: it is back where
        /// the app would have put it anyway, so the app gets it back and may
        /// dodge it again. That is what the home detent is for — without it a
        /// number, once slid, could only be handed back by undoing.
        public var readout: MeasureReadoutPlacement {
            MeasureReadoutPlacement(nudge: labelNudge, pinned: labelNudge != 0)
        }
    }

    /// How close to its own centred home a slid number has to come before it
    /// clicks back onto it, in screen points — the same reach every other
    /// measure snap uses. Without this detent a number that has been slid can
    /// only be re-centred by undoing, since nothing ever re-places it again.
    public static let homeDetent: CGFloat = 8

    /// Resolves one mouse-moved event into the caliper's new head offset and
    /// readout nudge.
    ///
    /// - Parameters:
    ///   - content: the caliper in DOCUMENT space, as it was when the drag began.
    ///   - pointer: the pointer now, document space.
    ///   - grabCross: where the pointer took hold ACROSS the line, relative to
    ///     the head — so a pill grabbed near its edge keeps that grip.
    ///   - grabAlong: the same grip ALONG the line, relative to the pill's centre.
    ///   - guides: where the other readouts on the picture centre, both axes.
    ///   - zoom: canvas zoom, so the snap reach is constant on screen.
    ///   - snapping: false while the free-drag modifier is held.
    ///   - slidesAlong: false leaves the number exactly where it was along the
    ///     line, so the drag is the older across-only one.
    public static func resolve(_ content: MeasureContent, pointer: CGPoint,
                               grabCross: CGFloat, grabAlong: CGFloat,
                               guides: EdgeSnapping.GuideLines, zoom: CGFloat,
                               snapping: Bool, slidesAlong: Bool = true,
                               holding held: SnapHold = .none) -> Placement {
        let horizontal = content.mode == .horizontal
        let chip = content.estimatedLabelSize
        let alongGuides = horizontal ? guides.vertical : guides.horizontal
        let crossGuides = horizontal ? guides.horizontal : guides.vertical
        // A number being dragged holds its lines the way every other drag on
        // the canvas does: the guide showing under the pill is the guide it
        // lands on, until the pointer is clearly away from it.
        let heldAlong = horizontal ? held.x : held.y
        let heldCross = horizontal ? held.y : held.x

        // Across the line, the head follows the pointer and the pill follows
        // the head — except where a placement holds the pill at its own standoff
        // and the pill does not follow at all. A snap the pill would not honour
        // is dropped rather than faked, so the guide never lies.
        let rawHead = (horizontal ? pointer.y : pointer.x) - grabCross - content.lineCross
        var head = rawHead
        var guideCross: CGFloat?
        if snapping, !crossGuides.isEmpty {
            let cross = chipCross(content, head: rawHead, chip: chip)
            if let line = EdgeSnapping.snapValue(cross, toGuides: crossGuides, zoom: zoom,
                                                 snapToPixelGrid: false,
                                                 holding: heldCross).guide {
                let moved = rawHead + (line - cross)
                if abs(chipCross(content, head: moved, chip: chip) - line) < 0.5 {
                    head = moved
                    guideCross = line
                }
            }
        }

        guard slidesAlong else {
            return Placement(headOffset: head, labelNudge: content.labelNudge,
                             guideX: horizontal ? nil : guideCross,
                             guideY: horizontal ? guideCross : nil)
        }

        // Along the line, the pill goes exactly where the pointer puts it: the
        // nudge is a plain shift, so nothing can refuse it.
        var target = (horizontal ? pointer.x : pointer.y) - grabAlong
        var guideAlong: CGFloat?
        let home = chipAlong(content, head: head, nudge: 0, chip: chip)
        if snapping {
            if let line = EdgeSnapping.snapValue(target, toGuides: alongGuides, zoom: zoom,
                                                 snapToPixelGrid: false,
                                                 holding: heldAlong).guide {
                target = line
                guideAlong = line
            } else if abs(target - home) <= EdgeSnapping.tolerance(zoom: zoom,
                                                                screenTolerance: homeDetent) {
                // Back on its own centre. No guide is drawn: a yellow line means
                // "you are lined up with that", and this is lined up with itself.
                target = home
            }
        }

        let placement = Placement(headOffset: head, labelNudge: target - home,
                                  guideX: horizontal ? guideAlong : guideCross,
                                  guideY: horizontal ? guideCross : guideAlong)
        return placement
    }

    /// Where the pill centres ACROSS the line with the head at `head`. Asked
    /// rather than derived, because a readout pushed clear of its subject keeps
    /// its own distance from the measuring line whatever the head does.
    private static func chipCross(_ content: MeasureContent, head: CGFloat,
                                  chip: CGSize) -> CGFloat {
        var probe = content
        probe.headOffset = head
        let centre = probe.labelPosition(chipSize: chip)
        return content.mode == .horizontal ? centre.y : centre.x
    }

    /// Where the pill centres ALONG the line with the head at `head` and the
    /// given nudge — its home when the nudge is zero.
    private static func chipAlong(_ content: MeasureContent, head: CGFloat,
                                  nudge: CGFloat, chip: CGSize) -> CGFloat {
        var probe = content
        probe.headOffset = head
        probe.labelNudge = nudge
        let centre = probe.labelPosition(chipSize: chip)
        return content.mode == .horizontal ? centre.x : centre.y
    }
}


/// A readout's own place along its measuring line, as a person left it.
///
/// Kept together because the two halves are one fact: the slide is only
/// meaningful with the pin that says a person, not the automatic placer, chose
/// it. Passing this to `MeasureBuilder.updating` is how a hand-placed number is
/// recorded; passing nil there means the drag did not touch the number.
public struct MeasureReadoutPlacement: Hashable, Sendable {
    /// The shift along the measuring line, from the number's centred home.
    public var nudge: CGFloat
    /// True once a person put the number here themselves.
    public var pinned: Bool

    public init(nudge: CGFloat, pinned: Bool) {
        self.nudge = nudge
        self.pinned = pinned
    }
}
