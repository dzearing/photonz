import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A move with a hold in it shows its keys on the strip.**
///
/// A punch in that pushes in, holds, and pulls back out is ONE motion with four
/// keys on it (`MotionStop`). The strip drew it as a single rounded bar, so the
/// four seconds it covers said that something happens and nothing about where
/// the camera arrives, how long it sits there, or when it leaves — while the
/// row in the side column right above it read "100% → 200% → 200% → 100%".
///
/// Everything a mark on that bar needs is arithmetic, so it is all here and
/// none of it is in the view: where each key falls, what it reads, where one of
/// them may be dragged to, and what happens to all of them when the bar itself
/// is moved or stretched.
@Suite("Keys drawn on a bar")
struct MotionStripKeysTests {

    static func shape(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    /// The punch in: in over a second, hold, out over a second.
    static func punchIn(start: Int = 800, over: Int = 4400) -> LayerMotion {
        LayerMotion(property: .scale, from: .number(100), to: .number(100),
                    timing: MotionTiming(startMS: start, durationMS: over),
                    repeats: .once,
                    stops: [MotionStop(atMS: start + 1000, value: .number(200)),
                            MotionStop(atMS: start + 3400, value: .number(200))])
    }

    static func document(_ motion: LayerMotion) -> PhotonzDocument {
        var layer = Self.shape("Tutorial Sample")
        layer.motions = [motion]
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [layer]
        return doc
    }

    // MARK: - What the lane carries

    @Test func aMoveWithKeysInTheMiddleCarriesThemOnItsLane() {
        let groups = Self.document(Self.punchIn()).motionStrip()
        let lane = groups[0].lanes[0]
        #expect(lane.keys.map(\.ms) == [1800, 4200])
        // What the property IS at each of them, in the words the side column
        // uses, so the mark can say it rather than being an anonymous tick.
        #expect(lane.keys.map(\.reading) == ["200%", "200%"])
    }

    @Test func aPlainTwoKeyMoveCarriesNoneAndSoDrawsAsItDidBefore() {
        let plain = LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                                timing: MotionTiming(startMS: 0, durationMS: 900))
        let groups = Self.document(plain).motionStrip()
        #expect(groups[0].lanes[0].keys.isEmpty)
    }

    @Test func keysAreDrawnOnTheDocumentsClockLikeTheBarTheySitOn() {
        // A part inside something that occupies time inherits its clock, and a
        // key is on the same clock as the bar under it or it is drawn in the
        // wrong place (`motionStrip()`).
        var clip = Self.shape("Piece 1")
        clip.time = LayerTime(inMS: 4000, outMS: 12000)
        clip.motions = [Self.punchIn(start: 0, over: 4400)]
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [clip]
        let lane = doc.motionStrip()[0].lanes[0]
        #expect(lane.timing.startMS == 4000)
        #expect(lane.keys.map(\.ms) == [5000, 7400])
    }

    @Test func aKeyOutsideTheBarIsNotDrawn() {
        // `LayerMotion.keys` drops them rather than clamping, because a key
        // past the end means the bar should have been longer. The strip shows
        // exactly what plays.
        let odd = LayerMotion(property: .scale, from: .number(100), to: .number(100),
                              timing: MotionTiming(startMS: 0, durationMS: 1000),
                              stops: [MotionStop(atMS: 400, value: .number(200)),
                                      MotionStop(atMS: 5000, value: .number(50))])
        let lane = Self.document(odd).motionStrip()[0].lanes[0]
        #expect(lane.keys.map(\.ms) == [400])
    }

    // MARK: - Dragging one of them

    @Test func aKeyMovesWithTheHand() {
        let drag = MotionStopDrag(keys: [800, 1800, 4200, 5200], middle: 1)
        #expect(drag?.heldMS == 4200)
        #expect(drag?.moved(byMS: 600) == 4800)
        #expect(drag?.moved(byMS: -600) == 3600)
    }

    @Test func aKeyStopsShortOfTheKeysEitherSideOfIt() {
        let drag = MotionStopDrag(keys: [800, 1800, 4200, 5200], middle: 1)
        // Past its neighbour it would swap two keys over, which draws one move
        // as a different move. It stops a hair short of each instead.
        #expect(drag?.moved(byMS: 9000) == 5200 - MotionStopDrag.shortestMS)
        #expect(drag?.moved(byMS: -9000) == 1800 + MotionStopDrag.shortestMS)
    }

    @Test func aKeyWithNoRoomEitherSideStaysWhereItIs() {
        // Its neighbours are ten milliseconds apart, so there is nowhere it
        // could go that is not on top of one of them.
        let drag = MotionStopDrag(keys: [0, 100, 105, 110, 200], middle: 1)
        #expect(drag?.moved(byMS: 40) == 105)
        #expect(drag?.moved(byMS: -40) == 105)
    }

    @Test func theTwoEndsAreNotKeysADragCanTake() {
        // They are the bar's own handles and they already have a gesture.
        #expect(MotionStopDrag(keys: [800, 1800, 5200], middle: -1) == nil)
        #expect(MotionStopDrag(keys: [800, 1800, 5200], middle: 1) == nil)
        #expect(MotionStopDrag(keys: [800, 5200], middle: 0) == nil)
    }

    // MARK: - What it writes down

    @Test func movingAKeyLeavesTheRestOfTheMoveAlone() {
        let moved = Self.punchIn().movingKey(1, toMS: 4800)
        #expect(moved.timing == MotionTiming(startMS: 800, durationMS: 4400))
        #expect(moved.from == .number(100))
        #expect(moved.to == .number(100))
        #expect(moved.keys.map(\.atMS) == [800, 1800, 4800, 5200])
        // The key kept its VALUE: a drag along the bar is about when, never
        // about what.
        #expect(moved.keys.map(\.value) == [.number(100), .number(200),
                                            .number(200), .number(100)])
    }

    @Test func aKeyCannotBeWrittenOutsideTheBarItIsOn() {
        let moved = Self.punchIn().movingKey(0, toMS: 99000)
        #expect(moved.keys.count == 4)
        #expect(moved.keys[1].atMS < moved.timing.endMS)
    }

    @Test func askingForAKeyThatIsNotThereChangesNothing() {
        let motion = Self.punchIn()
        #expect(motion.movingKey(7, toMS: 2000) == motion)
        #expect(motion.movingKey(-1, toMS: 2000) == motion)
    }

    // MARK: - The whole bar still carries them

    @Test func movingTheWholeBarCarriesItsKeysAlong() {
        let lane = Self.document(Self.punchIn()).motionStrip()[0].lanes[0]
        let later = lane.retimed(to: MotionTiming(startMS: 1800, durationMS: 4400))
        #expect(later.keys.map(\.ms) == [2800, 5200])
        #expect(later.keys.map(\.reading) == lane.keys.map(\.reading))
    }

    @Test func stretchingTheWholeBarSpreadsItsKeysInProportion() {
        let lane = Self.document(Self.punchIn()).motionStrip()[0].lanes[0]
        // Twice as long, starting where it did: a key a quarter of the way
        // along stays a quarter of the way along.
        let slower = lane.retimed(to: MotionTiming(startMS: 800, durationMS: 8800))
        #expect(slower.keys.map(\.ms) == [2800, 7600])
    }

    @Test func aBarWithNoKeysRetimesToABarWithNoKeys() {
        let plain = LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                                timing: MotionTiming(startMS: 0, durationMS: 900))
        let lane = Self.document(plain).motionStrip()[0].lanes[0]
        let moved = lane.retimed(to: MotionTiming(startMS: 90, durationMS: 900))
        #expect(moved.timing.startMS == 90)
        #expect(moved.keys.isEmpty)
    }

    // MARK: - What the mark says out loud

    @Test func aMomentIsReadInTheUnitsItsRulerIsIn() {
        // A recording is read in seconds, because that is how long one is. A
        // lap stays in milliseconds, because ninety of them is the whole
        // reason the strip exists.
        #expect(MotionStripRuler(documentMS: 8000).reading(ofMS: 4200) == "4.2s")
        #expect(MotionStripRuler(cycleMS: 900).reading(ofMS: 450) == "450 ms")
    }
}
