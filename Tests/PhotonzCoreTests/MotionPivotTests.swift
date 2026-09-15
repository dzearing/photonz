import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What a turning layer turns AROUND.
///
/// Written before the model, which is the rule for `PhotonzCore`. A bell that
/// swings hangs from its mount, not from its middle, so a rotation that cannot
/// say where its pivot is has not described the animation anybody actually
/// asks for: with the pivot in the middle the bell rocks like a bobblehead.
///
/// The point is kept as a fraction of the layer's OWN box rather than as a
/// place on the canvas, which is what makes it survive the layer being moved
/// or resized, and what makes the three named spots values rather than a
/// separate kind of thing.
@Suite("A turning layer says what it turns around")
struct MotionPivotTests {

    // MARK: - Fixtures

    /// A 40x40 shape whose middle is (26, 24), top centre (26, 4) and bottom
    /// centre (26, 44).
    static func shape() -> Layer {
        Layer(name: "Bell",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 6, y: 4, width: 40, height: 40))
    }

    static func turning(_ pivot: MotionPivot) -> Layer {
        var layer = shape()
        var motion = LayerMotion.starting(.rotation, on: layer)
        motion.pivot = pivot
        layer.motions = [motion]
        return layer
    }

    // MARK: - The three named spots

    /// The names mean what they say, measured on the layer's own box. Top is
    /// y nought because the document model is top-left origin.
    @Test func eachNamedSpotLandsWhereItsNameSays() {
        let box = Self.shape().frame
        #expect(MotionPivot.centre.point(in: box) == CGPoint(x: 26, y: 24))
        #expect(MotionPivot.topCentre.point(in: box) == CGPoint(x: 26, y: 4))
        #expect(MotionPivot.bottomCentre.point(in: box) == CGPoint(x: 26, y: 44))
    }

    /// The menu is exactly the three the task asks for, in the order a bell
    /// makes sense in: where it is now, where it hangs from, where it stands on.
    @Test func theNamedSpotsAreOneSettledShortList() {
        #expect(MotionPivot.Named.allCases == [.centre, .topCentre, .bottomCentre])
        #expect(MotionPivot.Named.allCases.map(\.title)
                == ["Its centre", "Top centre", "Bottom centre"])
    }

    /// A pivot sitting on a named spot says so, and one somewhere of its own
    /// does not pretend to. That is what lets the row read "Top centre" after
    /// a drag that happened to land there.
    @Test func aPivotOnANamedSpotSaysWhichOne() {
        #expect(MotionPivot.topCentre.named == .topCentre)
        #expect(MotionPivot.centre.named == .centre)
        #expect(MotionPivot(unit: CGPoint(x: 0.5, y: -0.2)).named == nil)
    }

    // MARK: - Reading a point off the canvas and putting it back

    /// The drag hands in a place on the canvas; the row hands in two typed
    /// numbers. Both come back out as the same place.
    @Test func aPointReadOffTheBoxComesBackAsItself() {
        let box = Self.shape().frame
        let dropped = CGPoint(x: 26, y: -6)
        let pivot = MotionPivot(at: dropped, in: box)
        #expect(pivot.point(in: box) == dropped)
    }

    /// A mount ABOVE the shape that swings is the whole point of the feature,
    /// so a pivot is never clamped into the box it is a fraction of.
    @Test func aPivotIsAllowedOutsideTheLayerAltogether() {
        let box = Self.shape().frame
        let pivot = MotionPivot(at: CGPoint(x: 26, y: -16), in: box)
        #expect(pivot.unit.y < 0)
        #expect(pivot.point(in: box).y == -16)
    }

    /// Because it is a fraction of the layer's box rather than a place on the
    /// canvas, moving the bell carries its mount along. Stored as canvas
    /// numbers this is the bug: drag the bell and the swing tears loose.
    @Test func thePivotFollowsTheLayerWhenTheLayerMoves() {
        let pivot = MotionPivot(at: CGPoint(x: 26, y: -6), in: Self.shape().frame)
        var moved = Self.shape()
        moved.frame = moved.frame.offsetBy(dx: 100, dy: 50)
        #expect(pivot.point(in: moved.frame) == CGPoint(x: 126, y: 44))
    }

    /// A box with no width cannot say where along itself a point is, so it
    /// answers the middle rather than a NaN that would poison the transform
    /// and take the layer off the canvas.
    @Test func aBoxWithNoSizeAnswersItsMiddleRatherThanNothing() {
        let flat = CGRect(x: 10, y: 10, width: 0, height: 0)
        let pivot = MotionPivot(at: CGPoint(x: 40, y: 40), in: flat)
        #expect(pivot.unit == CGPoint(x: 0.5, y: 0.5))
        #expect(pivot.point(in: flat) == CGPoint(x: 10, y: 10))
    }

    // MARK: - What a fresh rotation arrives with

    /// The handle is on the picture the moment Rotation exists, in the middle
    /// of the layer, which is the step the walkthrough deliberately shows
    /// being WRONG before one drag repairs it.
    @Test func aFreshRotationArrivesPivotedOnTheMiddle() {
        let layer = Self.shape()
        let motion = LayerMotion.starting(.rotation, on: layer)
        #expect(motion.pivot == .centre)
        #expect(motion.turnsAbout.point(in: layer.frame) == CGPoint(x: 26, y: 24))
    }

    /// Nothing else has one. A fade or a slide has no axis to turn about, and
    /// a pivot sitting unused on one would be a number the row cannot explain.
    @Test func onlyARotationCarriesAPivot() {
        let layer = Self.shape()
        for property in MotionProperty.allCases where property != .rotation {
            #expect(LayerMotion.starting(property, on: layer).pivot == nil,
                    "\(property) should not carry a pivot")
        }
    }

    // MARK: - The one question everything asks

    /// `turnPivot` is what the renderer, the selection outline, the turn knob,
    /// the handles and the hit test all ask, so the motion's pivot has to be
    /// the answer it gives or the drawn pixels and the box round them would
    /// disagree.
    @Test func theLayerTurnsAboutTheMotionsPivot() {
        #expect(Self.turning(.topCentre).turnPivot == CGPoint(x: 26, y: 4))
        #expect(Self.turning(MotionPivot(unit: CGPoint(x: 0.5, y: -0.3))).turnPivot
                == CGPoint(x: 26, y: -8))
    }

    /// A layer that is not turning answers exactly what it answered before
    /// there were pivots at all, so nothing already drawn can move.
    @Test func aLayerWithNoTurnStillTurnsAboutItsMiddle() {
        #expect(Self.shape().turnPivot == CGPoint(x: 26, y: 24))
        var fading = Self.shape()
        fading.motions = [LayerMotion.starting(.opacity, on: fading)]
        #expect(fading.turnPivot == CGPoint(x: 26, y: 24))
    }

    /// The switch on the row stops the layer MOVING; it does not throw the
    /// numbers on that row away, and the pivot is one of them.
    @Test func switchingTheTurnOffKeepsItsPivot() {
        var layer = Self.turning(.topCentre)
        layer.motions?[0].isOn = false
        #expect(layer.turnPivot == CGPoint(x: 26, y: 4))
    }

    /// The box the selection outline draws is mapped through the same pivot,
    /// so the outline swings with the picture rather than staying behind it.
    @Test func theOutlineIsMappedThroughTheSamePivot() {
        var layer = Self.turning(.topCentre)
        layer.transform.rotation = .pi / 2
        let corners = layer.transformedCorners
        // A quarter turn clockwise about (26, 4), in a space whose y runs
        // DOWN: the top-left corner (6, 4) sits 20 to the pivot's left, which
        // is nine o'clock, and a quarter turn clockwise takes nine to twelve.
        #expect(abs(corners[0].x - 26) < 0.001)
        #expect(abs(corners[0].y + 16) < 0.001)
    }

    // MARK: - Writing it down

    /// A pivot is part of the document, so it survives being saved.
    @Test func aPivotSurvivesBeingWrittenAndRead() throws {
        let document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200),
                                       layers: [Self.turning(MotionPivot(unit: CGPoint(x: 0.5, y: -0.25)))])
        let data = try JSONEncoder().encode(document)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(read.layers[0].motions?[0].pivot == MotionPivot(unit: CGPoint(x: 0.5, y: -0.25)))
        #expect(read.layers[0].turnPivot == Self.turning(MotionPivot(unit: CGPoint(x: 0.5, y: -0.25))).turnPivot)
    }

    /// A motion written before pivots existed reads back with none, and none
    /// means the middle: the picture it drew yesterday is the picture it draws
    /// today.
    @Test func aTurnWrittenBeforePivotsExistedStillTurnsAboutItsMiddle() throws {
        var layer = Self.shape()
        var motion = LayerMotion.starting(.rotation, on: layer)
        motion.pivot = nil
        layer.motions = [motion]
        let data = try JSONEncoder().encode(layer)
        let read = try JSONDecoder().decode(Layer.self, from: data)
        #expect(read.motions?[0].pivot == nil)
        #expect(read.motions?[0].turnsAbout == .centre)
        #expect(read.turnPivot == CGPoint(x: 26, y: 24))
    }
}
