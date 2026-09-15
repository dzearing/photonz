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
}
