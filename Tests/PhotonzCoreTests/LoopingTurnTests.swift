import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A turn set on a repeating picture loops smoothly without extra keys
/// (task `a-looping-turn-comes-home-and-spins-evenly-witho`).
///
/// Reproduced 2026-11-07: keys of 0, 15 at 0.5 s and -15 at 1.5 s on a two
/// second lap held at -15 and restarted at 0, a fifteen degree jump every lap,
/// and a spin of 0 to 360 eased in and out, so it slowed to a stop at the lap
/// until somebody picked Linear by hand.
///
/// Pinned here: a turn that moves comes home with a real key at the lap end
/// holding its first angle; a key set within a frame of the lap end lands ON
/// it; a key on the lap end travels with the repeats mark; where the turn
/// passes through the seam the two seam keys nobody eased are straightened
/// there, so it neither stops nor kicks. Only turns, only on a picture whose
/// lap repeats, and nothing a person chose is overruled.
@Suite("A looping turn comes home and spins evenly")
struct LoopingTurnTests {

    static func picture() -> (doc: PhotonzDocument, id: UUID) {
        let bell = Layer(name: "Bell", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#336699")),
                         frame: CGRect(x: 100, y: 100, width: 80, height: 80))
        return (PhotonzDocument(canvasSize: CGSize(width: 600, height: 400), layers: [bell]), bell.id)
    }

    static func turn(_ doc: inout PhotonzDocument, _ id: UUID, to degrees: Double, atMS ms: Int) {
        doc.setKeyedValue(.number(degrees), layerID: id, .motion(.rotation), atDocumentTimeMS: ms)
    }

    /// The walk's swing: Add Key at the top, 15 at half a second, -15 at a
    /// second and a half, and nothing typed at the end.
    static func swing() -> (doc: PhotonzDocument, id: UUID) {
        var (doc, id) = picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        turn(&doc, id, to: 15, atMS: 500)
        turn(&doc, id, to: -15, atMS: 1500)
        return (doc, id)
    }

    /// The frame walk's spin: Animate ▸ Rotation at the top, then 360 typed
    /// where a click at the end of the ruler lands.
    static func spin() -> (doc: PhotonzDocument, id: UUID) {
        var (doc, id) = picture()
        doc.animate(layerID: id, .motion(.rotation), atDocumentTimeMS: 0)
        turn(&doc, id, to: 360, atMS: 1999)
        return (doc, id)
    }

    static func keys(_ doc: PhotonzDocument, _ id: UUID) -> [(ms: Int, degrees: Double)] {
        (doc.layer(id: id)?.keyedMotion(.rotation)?.keyframes ?? []).map { key in
            if case let .number(degrees) = key.value { return (key.atMS, degrees) }
            return (key.atMS, .nan)
        }
    }

    /// The angle as the picture PLAYS it, `ms` into the loop (past the lap is
    /// the next lap).
    static func angle(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Double {
        let lap = doc.motionCycleLengthMS
        guard let motion = doc.lappingKeys.layer(id: id)?.keyedMotion(.rotation),
              case let .number(degrees) = motion.value(atMS: ms, cycleMS: lap) else { return .nan }
        return degrees
    }

    /// The same angle with whole turns taken off, so 360 reads as 0.
    static func heading(_ degrees: Double) -> Double {
        var turned = degrees.truncatingRemainder(dividingBy: 360)
        if turned > 180 { turned -= 360 }
        if turned < -180 { turned += 360 }
        return turned
    }

    // MARK: - A swing comes home

    @Test func aSwingComesHomeWithAKeyAtTheLapEnd() {
        let (doc, id) = Self.swing()
        let keys = Self.keys(doc, id)
        #expect(keys.map(\.ms) == [0, 500, 1500, 2000])
        #expect(keys.map(\.degrees) == [0, 15, -15, 0])
    }

    @Test func theFrameEitherSideOfTheLapReadsTheSameAngle() {
        let (doc, id) = Self.swing()
        let before = Self.angle(doc, id, atMS: 1999)
        let after = Self.angle(doc, id, atMS: 2000)
        #expect(abs(before - after) < 1, "the lap ends at \(before) and starts at \(after)")
        // A frame either side, at thirty frames a second.
        let lastFrame = Self.angle(doc, id, atMS: 2000 - 33)
        let firstFrame = Self.angle(doc, id, atMS: 2000 + 33)
        #expect(abs(lastFrame - firstFrame) < 5)
    }

    @Test func aSwingDoesNotStopWhereTheLapStartsOver() {
        // It crosses its start on the way from -15 to 15, so it is moving
        // there: easing both sides of that key would park it at 0 every lap.
        let (doc, id) = Self.swing()
        let arriving = Self.angle(doc, id, atMS: 2000) - Self.angle(doc, id, atMS: 1950)
        let leaving = Self.angle(doc, id, atMS: 2050) - Self.angle(doc, id, atMS: 2000)
        #expect(arriving > 1, "it creeps into the seam: \(arriving) degrees in 50 ms")
        #expect(leaving > 1, "it creeps out of the seam: \(leaving) degrees in 50 ms")
        // ...and at one pace either side, rather than a kick.
        #expect(abs(arriving - leaving) < max(arriving, leaving) * 0.25)
    }

    @Test func theSeamIsACurveYouCanSeeAndChange() throws {
        let (doc, id) = Self.swing()
        let keys = try #require(doc.layer(id: id)?.keyedMotion(.rotation)?.keyframes)
        #expect(keys.first?.ease == .bezier)
        #expect(keys.last?.ease == .bezier)
        // The keys at the turning points are left as every new key is.
        #expect(keys[1].ease == nil)
        #expect(keys[2].ease == nil)
    }

    @Test func aTurnThatOnlyGoesOutAndBackIsEasedAsEver() {
        // 0, 15 and home: it turns round at the seam, and easing there is right.
        var (doc, id) = Self.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        Self.turn(&doc, id, to: 15, atMS: 500)
        let keys = doc.layer(id: id)?.keyedMotion(.rotation)?.keyframes ?? []
        #expect(keys.map(\.atMS) == [0, 500, 2000])
        #expect(keys.allSatisfy { $0.ease == nil })
    }

    @Test func theFileComesHomeToo() throws {
        let (doc, id) = Self.swing()
        let motion = try #require(doc.lappingKeys.layer(id: id)?.keyedMotion(.rotation))
        let stops = MotionSVG.stops(for: motion, cycleMS: 2000)
        #expect(stops.first?.ms == 0)
        #expect(stops.last?.ms == 2000)
        #expect(stops.first?.value == stops.last?.value)
        let file = SVGExport.write(doc, animation: .moving(cycleMS: 2000)).text
        #expect(file.contains(#"keyTimes="0;0.25;0.75;1""#))
    }

    @Test func theHomeKeyFollowsTheFirstAngle() {
        var (doc, id) = Self.swing()
        Self.turn(&doc, id, to: 5, atMS: 0)
        #expect(Self.keys(doc, id).map(\.degrees) == [5, 15, -15, 5])
    }

    @Test func anAngleTypedAtTheLapEndIsKept() {
        var (doc, id) = Self.swing()
        Self.turn(&doc, id, to: 30, atMS: 1999)
        #expect(Self.keys(doc, id).map(\.ms) == [0, 500, 1500, 2000])
        #expect(Self.keys(doc, id).last?.degrees == 30)
        // ...and moving the first key no longer drags a key somebody typed.
        Self.turn(&doc, id, to: 5, atMS: 0)
        #expect(Self.keys(doc, id).last?.degrees == 30)
    }

    @Test func oneKeyDoesNotGrowAHomeKey() {
        var (doc, id) = Self.picture()
        doc.animate(layerID: id, .motion(.rotation), atDocumentTimeMS: 0)
        Self.turn(&doc, id, to: 10, atMS: 0)
        #expect(Self.keys(doc, id).map(\.ms) == [0])
    }

    @Test func aPictureThatPlaysOnceIsLeftAsItWas() {
        var (doc, id) = Self.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        doc.setKeyLapRepeats(false)
        Self.turn(&doc, id, to: 15, atMS: 500)
        #expect(Self.keys(doc, id).map(\.ms) == [0, 500])
    }

    @Test func aMoveIsLeftAsItWas() {
        var (doc, id) = Self.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        doc.setKeyedValue(.point(CGPoint(x: 100, y: 100)), layerID: id, .motion(.position), atDocumentTimeMS: 0)
        doc.setKeyedValue(.point(CGPoint(x: 200, y: 100)), layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        #expect(doc.layer(id: id)?.keyedMotion(.position)?.keyframes.map(\.atMS) == [0, 1000])
    }

    @Test func aCurveSomebodyChoseIsKept() throws {
        var (doc, id) = Self.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0, ease: .hold)
        doc.setKeyedValue(.number(15), layerID: id, .motion(.rotation), atDocumentTimeMS: 500, ease: .hold)
        doc.setKeyedValue(.number(-15), layerID: id, .motion(.rotation), atDocumentTimeMS: 1500, ease: .hold)
        let keys = try #require(doc.layer(id: id)?.keyedMotion(.rotation)?.keyframes)
        #expect(keys.map(\.atMS) == [0, 500, 1500, 2000])
        #expect(keys.first?.ease == .hold)
    }

    // MARK: - A spin goes round evenly

    @Test func aKeySetAtTheEndOfTheRulerLandsOnTheLapEnd() {
        let (doc, id) = Self.spin()
        #expect(Self.keys(doc, id).map(\.ms) == [0, 2000])
        #expect(Self.keys(doc, id).map(\.degrees) == [0, 360])
    }

    @Test func aSpinGoesRoundAtASteadyPace() {
        let (doc, id) = Self.spin()
        for ms in stride(from: 0, through: 1900, by: 100) {
            let angle = Self.angle(doc, id, atMS: ms)
            #expect(abs(angle - Double(ms) * 0.18) < 0.5, "at \(ms) ms it is at \(angle)")
        }
        let before = Self.heading(Self.angle(doc, id, atMS: 1999))
        let after = Self.heading(Self.angle(doc, id, atMS: 2000))
        #expect(abs(before - after) < 1)
    }

    @Test func theSpinSaysLinearOnTheStrip() throws {
        let (doc, id) = Self.spin()
        let keys = try #require(doc.layer(id: id)?.keyedMotion(.rotation)?.keyframes)
        #expect(keys.map(\.ease) == [.linear, .linear])
    }

    @Test func theSpinIsWrittenStraightIntoTheFile() {
        let (doc, _) = Self.spin()
        let file = SVGExport.write(doc, animation: .moving(cycleMS: 2000)).text
        #expect(file.contains(#"calcMode="linear""#))
        #expect(!file.contains("keySplines"))
        #expect(file.contains(#"keyTimes="0;1""#))
    }

    @Test func aSpinNeedsNoHomeKey() {
        // 360 is where it started, turned once: home already.
        var (doc, id) = Self.picture()
        doc.animate(layerID: id, .motion(.rotation), atDocumentTimeMS: 0)
        Self.turn(&doc, id, to: 360, atMS: 1500)
        #expect(Self.keys(doc, id).map(\.ms) == [0, 1500])
    }

    // MARK: - A key on the lap end rides the repeats mark

    @Test func aKeyOnTheLapEndTravelsWithTheRepeatsMark() {
        var (doc, id) = Self.swing()
        doc.setKeyLapLength(3000)
        #expect(doc.motionCycleLengthMS == 3000)
        #expect(Self.keys(doc, id).map(\.ms) == [0, 500, 1500, 3000])
        doc.setKeyLapLength(1600)
        #expect(Self.keys(doc, id).map(\.ms) == [0, 500, 1500, 1600])
    }

    @Test func theRepeatsMarkStopsAtTheLastKeyThatDoesNotRideIt() {
        let (doc, _) = Self.swing()
        #expect(doc.shortestDraggedKeyLapMS == 1501)
        // A set_timing call still counts every key, the one on the end too.
        #expect(doc.shortestKeyLapMS == 2001)
    }
}

@Suite("Reading a lap's seam")
struct LapSeamReadingTests {

    @Test func aSwingReadsNoJumpAndKeepsMovingThroughTheSeam() throws {
        let (doc, _) = LoopingTurnTests.swing()
        let reading = try #require(doc.lapSeamReadings().first)
        #expect(reading.jump < 1)
        #expect(reading.arriving > 1)
        #expect(reading.leaving > 1)
    }

    @Test func aSpinReadsASteadyPace() throws {
        let (doc, _) = LoopingTurnTests.spin()
        let reading = try #require(doc.lapSeamReadings().first)
        #expect(reading.jump < 1)
        #expect(reading.paceSpread < 0.05)
    }

    @Test func theOldSwingReadsItsJump() throws {
        // What the walk used to get: keys typed straight in, nothing at the end.
        var (doc, id) = LoopingTurnTests.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        let motion = LayerMotion.keyed(.rotation, atMS: 0, value: .number(0))
            .settingKey(atMS: 500, value: .number(15)).settingKey(atMS: 1500, value: .number(-15))
        doc.updateLayer(id: id) { $0.motions = [motion] }
        let reading = try #require(doc.lapSeamReadings().first)
        #expect(abs(reading.jump - 15) < 0.5)
    }

    @Test func anEasedSpinReadsUneven() throws {
        var (doc, id) = LoopingTurnTests.picture()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 0)
        let motion = LayerMotion.keyed(.rotation, atMS: 0, value: .number(0))
            .settingKey(atMS: 2000, value: .number(360))
        doc.updateLayer(id: id) { $0.motions = [motion] }
        let reading = try #require(doc.lapSeamReadings().first)
        #expect(reading.paceSpread > 0.5)
    }
}
