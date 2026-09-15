import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The line under the canvas while a path's points are showing. It is the only
/// place the gestures are written down, so what it says when is a decision
/// worth a test rather than a string the canvas happens to pass along.
@Suite("What the path chip says")
struct PathEditHintTests {

    static let corner = PathAnchor(point: .zero)
    static let bend = PathAnchor(point: .zero, handleIn: CGPoint(x: -20, y: 0),
                                 handleOut: CGPoint(x: 20, y: 0), kind: .smooth)
    static let halfLeaving = PathAnchor(point: .zero, handleOut: CGPoint(x: 20, y: 0))
    static let halfArriving = PathAnchor(point: .zero, handleIn: CGPoint(x: -20, y: 0))

    @Test func withNothingPickedItSaysHowToStart() {
        #expect(PathEditHint.line(picked: 0) == PathEditHint.opening)
    }

    @Test func withSeveralPickedItTalksAboutAllOfThem() {
        #expect(PathEditHint.line(picked: 3) == PathEditHint.severalPicked)
    }

    /// A hard corner has no levers on it, so a line telling you to drag one is
    /// pointing at something that is not there.
    @Test func aHardCornerIsNotToldToDragALeverItHasNot() {
        let line = PathEditHint.line(picked: 1, anchor: Self.corner)
        #expect(line == PathEditHint.cornerPicked)
        #expect(!line.contains("lever"))
    }

    @Test func aBendIsToldBothWaysToChangeItsTwoSides() {
        let line = PathEditHint.line(picked: 1, anchor: Self.bend)
        #expect(line == PathEditHint.bendPicked)
        #expect(line.contains("Double click"), "the way to straighten one side")
        #expect(line.contains("Option"), "and the way to free the two sides")
    }

    /// The case this is all for: the chip names the state you are in and the
    /// way back out of it, in both directions.
    @Test func aPointCurvedOnOneSideSaysSoWhicheverSideItIs() {
        #expect(PathEditHint.line(picked: 1, anchor: Self.halfLeaving) == PathEditHint.halfPicked)
        #expect(PathEditHint.line(picked: 1, anchor: Self.halfArriving) == PathEditHint.halfPicked)
        #expect(PathEditHint.halfPicked.contains("one side"))
    }

    /// One point picked but the canvas could not say which, which is what
    /// every caller before this did: the old line rather than an empty chip.
    @Test func onePointWithNoAnchorNamedFallsBackToTheGeneralLine() {
        #expect(PathEditHint.line(picked: 1) == PathEditHint.bendPicked)
    }

    /// The Pen stays in hand after a shape lands, so the chip somebody reads at
    /// the exact moment they want to curve a corner is the one shown WITH THE
    /// PEN. It cannot offer the one gesture the Pen cannot do.
    @Test func withThePenInHandItOffersOnlyWhatThePenCanDo() {
        let line = PathEditHint.line(picked: 0, penInHand: true)
        #expect(line == PathEditHint.penOpening)
        #expect(line.contains("Drag a point"), "moving a point")
        #expect(line.contains("Double click"), "curving one")
        #expect(!line.contains("outline"),
                "the outline double click adds a point, and the Pen cannot reach it")
    }

    /// With the Pen in hand a press off the points still starts another shape,
    /// so the chip says so rather than leaving somebody thinking the tool has
    /// changed under them.
    @Test func thePenLineSaysThePenStillDraws() {
        #expect(PathEditHint.penOpening.lowercased().contains("draw another"))
    }

    /// A point picked says the same things whichever tool is in hand: the
    /// gestures on a POINT are the same ones.
    @Test func aPickedPointSaysTheSameWithEitherToolInHand() {
        #expect(PathEditHint.line(picked: 1, anchor: Self.corner, penInHand: true)
                == PathEditHint.cornerPicked)
        #expect(PathEditHint.line(picked: 3, penInHand: true) == PathEditHint.severalPicked)
    }

    /// A turned path cannot be reshaped, and until now it said nothing at all:
    /// the points simply were not there. The line has to name the way back.
    @Test func aTurnedPathSaysWhyItsPointsAreNotThere() {
        #expect(PathEditHint.turned.contains("turned"))
        #expect(PathEditHint.turned.contains("Set A back to 0"),
                "the field that straightens it")
        #expect(PathEditHint.turned.contains("Position & Size"),
                "spelled the way the panel spells it (LayerSection.geometry)")
        #expect(PathEditHint.turned != PathEditHint.opening)
    }
}
