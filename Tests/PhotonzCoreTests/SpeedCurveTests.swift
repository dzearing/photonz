import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The speed curve under a clip (`SpeedCurve.swift`, the mock's `.scplot` in
/// `docs/design/mocks/pages/video-speed.html`), and the stops it drags: a stop
/// moved in time and in speed, a stop taken to nought, and a freeze held.
///
/// The numbers are worked by hand, on eight seconds of recording with a stop
/// three seconds in at 4x (`SpeedRampTests.rampedToFour`): up from 1x to 4x
/// over 1200 ms of timeline, back down over 2000 ms.
struct SpeedCurveTests {

    static func rampedToFour() -> ClipPieces { SpeedRampTests.rampedToFour() }

    // MARK: - The curve, on the clip's own clock

    @Test func theCurveRunsThroughEveryStopInTimelineTime() throws {
        let curve = SpeedCurve(Self.rampedToFour())
        #expect(curve.lengthMS == 3200)
        // Straight between stops: the speed changes evenly in timeline time.
        #expect(curve.points.map(\.timelineMS) == [0, 1200, 3200])
        #expect(curve.points.map(\.speed) == [1, 4, 1])
        #expect(abs(curve.speed(atMS: 600) - 2.5) < 1e-9)
        #expect(curve.handles.map(\.timelineMS) == [0, 1200, 3200])
        #expect(curve.handles.map(\.kind) == [.stop, .stop, .stop])
    }

    @Test func aPieceWithNoStopsIsAFlatLineAtItsSpeed() {
        let clip = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 2000, speedPercent: 200)],
                              sourceLengthMS: 8000)
        let curve = SpeedCurve(clip)
        #expect(curve.points.map(\.speed) == [2, 2])
        #expect(curve.handles.isEmpty)
        #expect(curve.bands.map(\.band) == [.fast])
    }

    @Test func holdSteps() throws {
        var clip = Self.rampedToFour()
        _ = clip.setRampBlend(ofPiece: 0, .hold)
        let curve = SpeedCurve(clip)
        // 3 s at 1x, then 5 s at 4x.
        // The step down to the last stop's own speed is drawn at its stop,
        // as the mock draws a Hold.
        #expect(curve.points.map(\.timelineMS) == [0, 3000, 3000, 4250, 4250])
        #expect(curve.points.map(\.speed) == [1, 1, 4, 4, 1])
    }

    // MARK: - Bands, tinted the way the mock tints them

    @Test func theBandsAreTheMocksFourAtTheMocksEdges() {
        #expect(SpeedBand(speed: 0) == .freeze)
        #expect(SpeedBand(speed: 0.05) == .freeze)
        #expect(SpeedBand(speed: 0.5) == .slow)
        #expect(SpeedBand(speed: 0.85) == .normal)
        #expect(SpeedBand(speed: 1.15) == .normal)
        #expect(SpeedBand(speed: 1.2) == .fast)
        #expect(SpeedBand.fast.hex == "#ff5d8f")
        #expect(SpeedBand.slow.hex == "#12c2e9")
        #expect(SpeedBand.normal.hex == "#9a5cff")
        #expect(SpeedBand.freeze.hex == "#febc2e")
    }

    @Test func aRampCrossesItsBandsWhereTheLineCrossesTheirEdges() throws {
        let curve = SpeedCurve(Self.rampedToFour())
        let bands = curve.bands
        #expect(bands.map(\.band) == [.normal, .fast, .normal])
        // 1x to 4x across 1200 ms crosses 1.15x a twentieth of the way up.
        #expect(abs(bands[0].endMS - 60) < 1e-6)
        #expect(abs(bands[2].startMS - (3200 - 100)) < 1e-6)
    }

    // MARK: - Dragging a stop

    @Test func draggingAStopUpChangesItsSpeedAndTheClipFollows() throws {
        var clip = Self.rampedToFour()
        let m1 = clip.moveSpeedStop(ofPiece: 0, stop: 1, toOffsetMS: nil, percent: 200)
        #expect(m1)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops[1] == SpeedStop(sourceMS: 3000, speedPercent: 200))
        // 2*3000/3 + 2*5000/3
        #expect(abs(clip.totalLengthMS - 5333) <= 1)
    }

    @Test func draggingAStopSidewaysLandsItUnderTheHand() throws {
        var clip = Self.rampedToFour()
        let m2 = clip.moveSpeedStop(ofPiece: 0, stop: 1, toOffsetMS: 2000, percent: 400)
        #expect(m2)
        let at = try #require(clip.timelineMS(ofStop: 1, inPiece: 0))
        #expect(abs(at - 2000) <= 1)
        // The ends never move, and the frames they read never move.
        #expect(clip.piece(at: 0)?.speedRamp?.stops.first?.sourceMS == 0)
        #expect(clip.piece(at: 0)?.sourceOutMS == 8000)
    }

    @Test func aStopCannotBeDraggedPastItsNeighbours() throws {
        var clip = Self.rampedToFour()
        _ = clip.moveSpeedStop(ofPiece: 0, stop: 1, toOffsetMS: 99_000, percent: 400)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops.count == 3)
        #expect(ramp.stops[1].sourceMS < 8000)
        #expect(ramp.stops[1].sourceMS > 7900)
    }

    @Test func theEndStopsOnlyMoveUpAndDown() throws {
        var clip = Self.rampedToFour()
        _ = clip.moveSpeedStop(ofPiece: 0, stop: 0, toOffsetMS: 500, percent: 200)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops[0] == SpeedStop(sourceMS: 0, speedPercent: 200))
    }

    @Test func aDragThatChangesNothingIsRefused() {
        var clip = Self.rampedToFour()
        let m3 = clip.moveSpeedStop(ofPiece: 0, stop: 1, toOffsetMS: nil, percent: 400)
        #expect(!m3)
    }

    @Test func theHandSnapsToTheMocksNiceSpeeds() {
        #expect(SpeedCurve.snapped(0.97) == 1)
        #expect(SpeedCurve.snapped(0.04) == 0)
        #expect(SpeedCurve.snapped(1.3) == 1.3)
        #expect(SpeedCurve.percent(forSpeed: 0.04) == 0)
        #expect(SpeedCurve.percent(forSpeed: 0.095) == 10)
        #expect(SpeedCurve.percent(forSpeed: 3.4) == 300)
    }

    // MARK: - Nought: one frame, and a freeze

    @Test func aStopAtNoughtStopsThePictureForASingleFrame() throws {
        var clip = Self.rampedToFour()
        let m4 = clip.moveSpeedStop(ofPiece: 0, stop: 1, toOffsetMS: nil, percent: 0)
        #expect(m4)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops[1].speedPercent == 0)
        #expect(ramp.stops[1].holdMS == 0)
        // 1x down to nought over 3 s of recording takes 6 s; nought up to 1x
        // over 5 s takes 10 s. It ends, which is the point.
        #expect(abs(clip.totalLengthMS - 16000) <= 1)
        #expect(abs((clip.sourceMS(atMS: 6000) ?? 0) - 3000) <= 1)
        let curve = SpeedCurve(clip)
        #expect(curve.points.map(\.speed) == [1, 0, 1])
    }

    @Test func freezeHoldsTheStopsFrameAndDrawsTwoZerosSideBySide() throws {
        var clip = Self.rampedToFour()
        let m5 = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 1000)
        #expect(m5)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops[1] == SpeedStop(sourceMS: 3000, speedPercent: 0, holdMS: 1000))
        #expect(abs(clip.totalLengthMS - 17000) <= 1)
        // Through the hold the same frame shows.
        #expect(abs((clip.sourceMS(atMS: 6000) ?? 0) - 3000) <= 1)
        #expect(clip.sourceMS(atMS: 6500) == 3000)
        #expect(abs((clip.sourceMS(atMS: 7000) ?? 0) - 3000) <= 1)
        #expect((clip.sourceMS(atMS: 7500) ?? 0) > 3000)
        let curve = SpeedCurve(clip)
        #expect(curve.handles.map(\.kind) == [.stop, .stop, .holdEnd, .stop])
        #expect(curve.handles.map(\.speed) == [1, 0, 0, 1])
        #expect(abs(curve.handles[2].timelineMS - 7000) < 1)
        let freeze = try #require(curve.bands.first { $0.band == .freeze })
        #expect(freeze.endMS - freeze.startMS >= 1000)
    }

    @Test func draggingTheSecondZeroSetsHowLongTheFreezeHolds() throws {
        var clip = Self.rampedToFour()
        _ = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 1000)
        let m6 = clip.setSpeedStopHold(ofPiece: 0, stop: 1, holdMS: 2500)
        #expect(m6)
        #expect(abs(clip.totalLengthMS - 18500) <= 1)
        let m7 = clip.setSpeedStopHold(ofPiece: 0, stop: 1, holdMS: -40)
        #expect(m7)
        #expect(clip.piece(at: 0)?.speedRamp?.stops[1].holdMS == 0)
        let m8 = clip.setSpeedStopHold(ofPiece: 0, stop: 0, holdMS: 500)
        #expect(!m8)
    }

    @Test func twoZerosOnNeighbouringFramesAreNotAllowed() throws {
        var clip = Self.rampedToFour()
        _ = clip.addSpeedStop(atMS: 3000)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops.count == 4)
        let m9 = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 500)
        #expect(m9)
        #expect(!clip.canFreezeSpeedStop(ofPiece: 0, stop: 2))
        let m10 = clip.freezeSpeedStop(ofPiece: 0, stop: 2, holdMS: 500)
        #expect(!m10)
        // A drag to the floor beside a zero stops at the slowest speed.
        _ = clip.moveSpeedStop(ofPiece: 0, stop: 2, toOffsetMS: nil, percent: 0)
        #expect(clip.piece(at: 0)?.speedRamp?.stops[2].speedPercent == ClipPiece.slowestPercent)
    }

    @Test func holdBlendLeavesAZeroAtTheNextStopsSpeed() throws {
        var clip = Self.rampedToFour()
        _ = clip.setRampBlend(ofPiece: 0, .hold)
        _ = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 1000)
        // 3 s at 1x, a second held, then 5 s at the last stop's 1x.
        #expect(abs(clip.totalLengthMS - 9000) <= 1)
    }

    @Test func aZeroStopWithItsHoldSurvivesBeingWrittenDown() throws {
        var clip = Self.rampedToFour()
        _ = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 750)
        let piece = try #require(clip.piece(at: 0))
        let data = try JSONEncoder().encode(piece)
        let back = try JSONDecoder().decode(ClipPiece.self, from: data)
        #expect(back == piece)
        // A stop that is not a freeze writes no hold at all.
        let plain = try JSONEncoder().encode(SpeedStop(sourceMS: 10, speedPercent: 100))
        #expect(String(decoding: plain, as: UTF8.self).contains("hold") == false)
        #expect(SpeedStop(sourceMS: 10, speedPercent: 100, holdMS: 500).holdMS == 0)
    }

    @Test func theFramesStillAlwaysMoveForwardThroughAFreeze() {
        var clip = Self.rampedToFour()
        _ = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 1000)
        var last = -1
        for ms in stride(from: 0, to: clip.totalLengthMS, by: 37) {
            let frame = clip.sourceMS(atMS: ms) ?? -1
            #expect(frame >= last)
            last = frame
        }
    }

    @Test func theStopsSpeedListOffersFreeze() {
        #expect(SpeedStopNames.speeds.first == 0)
        #expect(SpeedStopNames.speedTitle(0) == "Freeze")
        #expect(SpeedStopNames.speedTitle(100) == "Normal")
        #expect(SpeedStopNames.speedTitle(400) == "4x")
    }

    // MARK: - In the document

    @Test func eachDragIsOneStepOfUndo() throws {
        var start = ClipPiecesTests.document(ClipPiecesTests.clipLayer(lengthMS: 8000))
        let id = start.layers[0].id
        _ = start.addSpeedStop(id, atMS: 500 + 3000)
        var history = History(document: start)
        let was = history.current
        history.perform { _ = $0.moveSpeedStop(id, ofPiece: 0, stop: 1, toClipMS: 2000, percent: 200) }
        let moved = try #require(history.current.layer(id: id)?.clipPieces)
        #expect(moved.piece(at: 0)?.speedRamp?.stops[1].speedPercent == 200)
        #expect(abs((moved.timelineMS(ofStop: 1, inPiece: 0) ?? 0) - 2000) <= 1)
        history.perform { _ = $0.freezeSpeedStop(id, ofPiece: 0, stop: 1, holdMS: 1000) }
        history.perform { _ = $0.setSpeedStopHold(id, ofPiece: 0, stop: 1, holdMS: 300) }
        #expect(history.current.layer(id: id)?.clipPieces?.piece(at: 0)?.speedRamp?.stops[1].holdMS == 300)
        history.undo()
        history.undo()
        history.undo()
        #expect(history.current == was)
    }
}
