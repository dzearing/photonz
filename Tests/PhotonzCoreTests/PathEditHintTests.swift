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

    /// The turn itself says so, because the question that would have said it
    /// carries a "Don't ask again" and is gone the second time.
    @Test func aShapeThatJustBecameAPathSaysSo() {
        let one = PathEditHint.justTurned(paths: 1)
        #expect(one.contains("Turned into a path"))
        #expect(one.contains("Drag any point"), "and what to do with it now")
        #expect(one.contains("Command Z"), "and the way back out")
        #expect(!one.contains("\u{2014}"))

        // Several shapes at once can come out as several paths, or welded into
        // fewer, so the line counts what you actually got.
        #expect(PathEditHint.justTurned(paths: 3).contains("3 paths"))
        #expect(PathEditHint.justTurned(paths: 0) == one, "nothing left to count is still one line")
        #expect(PathEditHint.justTurned(paths: 1) != PathEditHint.opening)
    }

    /// A turned path used to carry a line of its own saying its points could
    /// not be dragged, and naming the field that straightened it. They can be
    /// dragged now (`PathEditSpace`), so there is nothing special to say about
    /// a turned shape and it gets the same lines every other shape gets.
    @Test func aTurnedPathIsToldTheSameThingsAsAnyOther() {
        #expect(PathEditHint.opening.contains("Drag a point"))
        #expect(!PathEditHint.opening.lowercased().contains("cannot"))
        #expect(!PathEditHint.penOpening.lowercased().contains("cannot"))
    }
}
