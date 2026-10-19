import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Speed stops: a piece whose speed changes across its length
/// (`SpeedRamp.swift`, `docs/design/mocks/pages/video-speed.html`).
///
/// The numbers are worked by hand. Eight seconds of recording, a stop added
/// three seconds in and set to four times: the ramp from normal up to 4x over
/// the first three seconds of recording takes 2 × 3000 / (1 + 4) = 1200 ms of
/// timeline, and the ramp back down over the last five takes
/// 2 × 5000 / (4 + 1) = 2000 ms, so the clip runs 3.2 s.
struct SpeedRampTests {

    static func recording(_ ms: Int = 8000) -> ClipPieces {
        ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: ms)], sourceLengthMS: ms)
    }

    /// The try path: a stop three seconds in, set to 4x.
    static func rampedToFour() -> ClipPieces {
        var clip = recording()
        _ = clip.addSpeedStop(atMS: 3000)
        _ = clip.setSpeedStop(ofPiece: 0, stop: 1, percent: 400)
        return clip
    }

    // MARK: - Adding a stop

    @Test func theFirstStopBringsTheTwoEndsWithItAndChangesNothing() throws {
        var clip = Self.recording()
        let r1 = clip.addSpeedStop(atMS: 3000)
        let added = try #require(r1)
        #expect(added.piece == 0)
        #expect(added.stop == 1)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops == [SpeedStop(sourceMS: 0, speedPercent: 100),
                               SpeedStop(sourceMS: 3000, speedPercent: 100),
                               SpeedStop(sourceMS: 8000, speedPercent: 100)])
        #expect(ramp.blend == .ramp)
        // Adding a stop is placing a handle, not changing the speed.
        #expect(clip.totalLengthMS == 8000)
        #expect(clip.sourceMS(atMS: 3000) == 3000)
        #expect(clip.isOnePlainPiece == false)
    }

    @Test func aStopAddedInsideARampKeepsTheCurveItLandedOn() throws {
        var clip = Self.rampedToFour()
        let before = clip.totalLengthMS
        let moment = 600
        let frame = try #require(clip.sourceMS(atMS: moment))
        let r2 = clip.addSpeedStop(atMS: moment)
        let added = try #require(r2)
        #expect(added.stop == 1)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops.count == 4)
        // The speed there was 2.5x (half way through a ramp from 1x to 4x in
        // timeline time), and that is what the new stop holds.
        #expect(ramp.stops[1] == SpeedStop(sourceMS: frame, speedPercent: 250))
        #expect(abs(clip.totalLengthMS - before) <= 1)
        #expect(abs((clip.sourceMS(atMS: moment) ?? 0) - frame) <= 1)
    }

    @Test func aStopIsNotAddedOnTopOfAnother() {
        var clip = Self.recording()
        _ = clip.addSpeedStop(atMS: 3000)
        let r3 = clip.addSpeedStop(atMS: 3000)
        #expect(r3 == nil)
        #expect(clip.piece(at: 0)?.speedRamp?.stops.count == 3)
    }

    @Test func aHeldFrameTakesNoStop() {
        var clip = Self.recording()
        _ = clip.holdFrame(atMS: 3000, forMS: 2000)
        let r4 = clip.addSpeedStop(atMS: 4000)
        #expect(r4 == nil)
    }

    // MARK: - The picture follows the ramp

    @Test func theClipRunsAsLongAsTheRampTakes() {
        let clip = Self.rampedToFour()
        #expect(clip.totalLengthMS == 3200)
        // What it reads from the file never changed: all eight seconds.
        #expect(clip.piece(at: 0)?.sourceInMS == 0)
        #expect(clip.piece(at: 0)?.sourceOutMS == 8000)
    }

    @Test func eachMomentShowsTheFrameTheEasedSpeedHasReached() {
        let clip = Self.rampedToFour()
        // Up the ramp: speed 1 + 3τ/1200, so the frame is τ + 3τ²/2400.
        #expect(clip.sourceMS(atMS: 0) == 0)
        #expect(clip.sourceMS(atMS: 600) == 1050)
        #expect(clip.sourceMS(atMS: 1200) == 3000)
        // Down the ramp: 4 − 3τ/2000 from the stop, so 4τ − 3τ²/4000.
        #expect(clip.sourceMS(atMS: 2200) == 6250)
        #expect(clip.sourceMS(atMS: 3200) == 8000)
    }

    @Test func holdKeepsEachStretchFlat() throws {
        var clip = Self.rampedToFour()
        let r5 = clip.setRampBlend(ofPiece: 0, .hold)
        #expect(r5)
        // Three seconds at 1x, then five at 4x.
        #expect(clip.totalLengthMS == 3000 + 1250)
        #expect(clip.sourceMS(atMS: 1500) == 1500)
        #expect(clip.sourceMS(atMS: 3500) == 5000)
        let r6 = clip.setRampBlend(ofPiece: 0, .hold)
        #expect(r6 == false)
    }

    @Test func theFramesAlwaysMoveForward() {
        let clip = Self.rampedToFour()
        var last = -1
        for ms in stride(from: 0, through: clip.totalLengthMS, by: 7) {
            let frame = clip.sourceMS(atMS: ms) ?? -1
            #expect(frame >= last)
            last = frame
        }
    }

    @Test func aMomentOfTheRecordingMapsBackToTheMomentItPlays() throws {
        let clip = Self.rampedToFour()
        let piece = try #require(clip.piece(at: 0))
        #expect(piece.offsetMS(ofSourceMS: 1050) == 600)
        #expect(piece.offsetMS(ofSourceMS: 3000) == 1200)
        #expect(piece.offsetMS(ofSourceMS: 6250) == 2200)
        #expect(clip.timelineMS(ofStop: 1, inPiece: 0) == 1200)
    }

    // MARK: - Changing a stop

    @Test func aStopsSpeedIsOneOfThePiecesSpeeds() throws {
        var clip = Self.rampedToFour()
        let r7 = clip.setSpeedStop(ofPiece: 0, stop: 1, percent: 99_000)
        #expect(r7)
        #expect(clip.piece(at: 0)?.speedRamp?.stops[1].speedPercent == ClipPiece.fastestPercent)
        let r8 = clip.setSpeedStop(ofPiece: 0, stop: 1, percent: ClipPiece.fastestPercent)
        #expect(r8 == false)
        let r9 = clip.setSpeedStop(ofPiece: 0, stop: 9, percent: 200)
        #expect(r9 == false)
        let r10 = clip.setSpeedStop(ofPiece: 0, stop: 1, percent: 0)
        #expect(r10 == false)
    }

    @Test func deletingAStopReshapesTheRamp() throws {
        var clip = Self.rampedToFour()
        let r11 = clip.deleteSpeedStop(ofPiece: 0, stop: 1)
        #expect(r11)
        let ramp = try #require(clip.piece(at: 0)?.speedRamp)
        #expect(ramp.stops.count == 2)
        #expect(clip.totalLengthMS == 8000)
        let r12 = clip.deleteSpeedStop(ofPiece: 0, stop: 5)
        #expect(r12 == false)
    }

    @Test func deletingTheLastStopIsTheSameAsResettingTheRamp() {
        var clip = Self.recording()
        _ = clip.addSpeedStop(atMS: 3000)
        for _ in 0..<3 { _ = clip.deleteSpeedStop(ofPiece: 0, stop: 0) }
        #expect(clip.piece(at: 0)?.speedRamp == nil)
        #expect(clip.isOnePlainPiece)
    }

    @Test func resetRampReturnsThePieceToOneSpeed() {
        var clip = Self.rampedToFour()
        let r13 = clip.resetRamp(ofPiece: 0)
        #expect(r13)
        #expect(clip.piece(at: 0)?.speedRamp == nil)
        #expect(clip.totalLengthMS == 8000)
        #expect(clip.isOnePlainPiece)
        let r14 = clip.resetRamp(ofPiece: 0)
        #expect(r14 == false)
    }

    @Test func resetRampReturnsToTheSpeedThePieceHadBefore() {
        var clip = Self.recording()
        _ = clip.setSpeed(ofPiece: 0, percent: 200)
        _ = clip.addSpeedStop(atMS: 1000)
        #expect(clip.piece(at: 0)?.speedRamp?.stops.allSatisfy { $0.speedPercent == 200 } == true)
        _ = clip.setSpeedStop(ofPiece: 0, stop: 1, percent: 1000)
        _ = clip.resetRamp(ofPiece: 0)
        #expect(clip.piece(at: 0)?.speedPercent == 200)
        #expect(clip.totalLengthMS == 4000)
    }

    @Test func pickingOneSpeedForTheWholePieceReplacesTheRamp() {
        var clip = Self.rampedToFour()
        let r15 = clip.setSpeed(ofPiece: 0, percent: 200)
        #expect(r15)
        #expect(clip.piece(at: 0)?.speedRamp == nil)
        #expect(clip.totalLengthMS == 4000)
    }

    // MARK: - Every other edit carries the stops on their frames

    @Test func aSplitRampKeepsEveryFrameWhereItWas() throws {
        var clip = Self.rampedToFour()
        let frames = stride(from: 0, through: 3200, by: 100).map { clip.sourceMS(atMS: $0) }
        let r16 = clip.split(atMS: 1200)
        #expect(r16)
        #expect(clip.count == 2)
        #expect(clip.piece(at: 0)?.sourceOutMS == 3000)
        #expect(clip.piece(at: 1)?.sourceInMS == 3000)
        #expect(clip.piece(at: 1)?.speedRamp == clip.piece(at: 0)?.speedRamp)
        #expect(clip.totalLengthMS == 3200)
        let after = stride(from: 0, through: 3200, by: 100).map { clip.sourceMS(atMS: $0) }
        #expect(after == frames)
    }

    @Test func aSplitRampJoinsBackIntoOnePiece() {
        var clip = Self.rampedToFour()
        let whole = clip
        _ = clip.split(atMS: 1700)
        #expect(clip.cut(at: 1)?.isContinuous == true)
        let r17 = clip.joinThroughEdit(atCut: 1)
        #expect(r17)
        #expect(clip.count == 1)
        #expect(clip.piece(at: 0)?.speedRamp == whole.piece(at: 0)?.speedRamp)
        #expect(clip.totalLengthMS == whole.totalLengthMS)
    }

    // MARK: - Cutting through a freeze

    /// The ramp to 4x with its stop frozen for a second: down from 1x to a
    /// standstill over three seconds of recording is 2 × 3000 / 1 = 6000 ms,
    /// the hold is 6000 to 7000, and back up over the last five is 10000 ms.
    static func frozenForASecond() -> ClipPieces {
        var clip = rampedToFour()
        _ = clip.freezeSpeedStop(ofPiece: 0, stop: 1, holdMS: 1000)
        return clip
    }

    @Test func aFrozenStopHoldsBetweenTheTwoRamps() {
        let clip = Self.frozenForASecond()
        #expect(clip.totalLengthMS == 17000)
        #expect(clip.sourceMS(atMS: 6000) == 3000)
        #expect(clip.sourceMS(atMS: 7000) == 3000)
        #expect(clip.sourceMS(atMS: 17000) == 8000)
    }

    @Test func aCutPartWayThroughAFreezeSharesTheHoldBetweenTheHalves() throws {
        var clip = Self.frozenForASecond()
        let frames = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        let r = clip.split(atMS: 6500)
        #expect(r)
        #expect(clip.count == 2)
        #expect(clip.totalLengthMS == 17000)
        let head = try #require(clip.piece(at: 0))
        let tail = try #require(clip.piece(at: 1))
        #expect(head.lengthMS == 6500)
        #expect(tail.sourceInMS == 3000)
        // The tail holds only the half second that was left of the freeze...
        #expect(tail.speedRamp?.stops.first { $0.sourceMS == 3000 }?.holdMS == 500)
        // ...and still runs to the recording's last frame.
        #expect(tail.sourceOutMS == 8000)
        let after = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        #expect(after == frames)
    }

    @Test func aCutWhereAFreezeEndsLeavesTheTailNothingToHold() throws {
        var clip = Self.frozenForASecond()
        let frames = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        _ = clip.split(atMS: 7000)
        let tail = try #require(clip.piece(at: 1))
        #expect(tail.sourceInMS == 3000)
        #expect(tail.speedRamp?.stops.first { $0.sourceMS == 3000 }?.holdMS == 0)
        #expect(tail.sourceOutMS == 8000)
        #expect(clip.sourceMS(atMS: 7100) != 3000)
        let after = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        #expect(after == frames)
    }

    @Test func aCutWhereAFreezeBeginsLeavesTheWholeHoldToTheTail() throws {
        var clip = Self.frozenForASecond()
        _ = clip.split(atMS: 6000)
        let tail = try #require(clip.piece(at: 1))
        #expect(tail.speedRamp == clip.piece(at: 0)?.speedRamp)
        #expect(tail.sourceOutMS == 8000)
        #expect(clip.totalLengthMS == 17000)
    }

    @Test func aCutThroughAFreezeJoinsBackIntoTheClipItWas() {
        var clip = Self.frozenForASecond()
        let whole = clip
        _ = clip.split(atMS: 6500)
        #expect(clip.cut(at: 1)?.isContinuous == true)
        let r = clip.joinThroughEdit(atCut: 1)
        #expect(r)
        #expect(clip == whole)
    }

    @Test func twoCutsInsideOneFreezeJoinBackIntoTheClipItWas() throws {
        var clip = Self.frozenForASecond()
        let whole = clip
        let frames = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        _ = clip.split(atMS: 6200)
        _ = clip.split(atMS: 6700)
        #expect(clip.count == 3)
        #expect(clip.piece(at: 1)?.speedRamp?.stops.first { $0.sourceMS == 3000 }?.holdMS == 800)
        #expect(clip.piece(at: 2)?.speedRamp?.stops.first { $0.sourceMS == 3000 }?.holdMS == 300)
        #expect(clip.piece(at: 2)?.sourceOutMS == 8000)
        let after = stride(from: 0, through: 17000, by: 100).map { clip.sourceMS(atMS: $0) }
        #expect(after == frames)
        _ = clip.joinThroughEdit(atCut: 2)
        _ = clip.joinThroughEdit(atCut: 1)
        #expect(clip == whole)
    }

    @Test func aTrimPulledInAndBackOutLandsOnTheSameFrame() throws {
        var clip = Self.rampedToFour()
        let r18 = clip.trimStart(ofPiece: 0, byMS: 500)
        #expect(r18)
        let pulled = try #require(clip.piece(at: 0))
        #expect(pulled.sourceInMS == Self.rampedToFour().sourceMS(atMS: 500))
        let r19 = clip.trimStart(ofPiece: 0, byMS: -500)
        #expect(r19)
        #expect(abs((clip.piece(at: 0)?.sourceInMS ?? -9) - 0) <= 1)
    }

    @Test func aTrimIsStoppedWhereTheRecordingRunsOut() throws {
        var clip = Self.rampedToFour()
        let r20 = clip.trimEnd(ofPiece: 0, byMS: -1000)
        #expect(r20)
        let range = try #require(clip.trimEndRange(ofPiece: 0))
        let out = try #require(range.out)
        // The last second of timeline was cut away, so about a second is spare.
        #expect(out >= 990 && out <= 1000)
        let r21 = clip.trimEnd(ofPiece: 0, byMS: out)
        #expect(r21)
        #expect((clip.piece(at: 0)?.sourceOutMS ?? 0) <= 8000)
        let r22 = clip.trimEnd(ofPiece: 0, byMS: 50)
        #expect(r22 == false)
        // Nothing before the first frame either.
        #expect(clip.trimStartRange(ofPiece: 0)?.out == 0)
    }

    // MARK: - What plays, and what it sounds like

    @Test func aRampedPiecePlaysSilent() throws {
        let clip = Self.rampedToFour()
        let piece = try #require(clip.piece(at: 0))
        #expect(piece.speedSound == .silentRamp)
        #expect(piece.playsSound == false)
        let played = try #require(clip.playback.first)
        #expect(played.speedRamp == piece.speedRamp)
        #expect(played.playsSound == false)
        #expect(played.sourceLengthMS == 8000)
        #expect(ClipSpeedSound.silentRamp.word == "Silent")
    }

    // MARK: - Written down

    @Test func aPieceWithNoStopsWritesExactlyWhatItAlwaysDid() throws {
        let old = #"{"lengthMS":4000,"sourceInMS":1000,"speedPercent":200}"#
        let piece = try JSONDecoder().decode(ClipPiece.self, from: Data(old.utf8))
        #expect(piece.speedRamp == nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(piece), as: UTF8.self) == old)
    }

    @Test func aRampSurvivesBeingWrittenDownAndReadBack() throws {
        var clip = Self.rampedToFour()
        _ = clip.setRampBlend(ofPiece: 0, .hold)
        let written = try JSONEncoder().encode(clip)
        let read = try JSONDecoder().decode(ClipPieces.self, from: written)
        #expect(read == clip)
        #expect(read.totalLengthMS == clip.totalLengthMS)
    }

    // MARK: - In the document

    @Test func theClipOnTheTimelineChangesLengthWithTheRamp() throws {
        var doc = ClipPiecesTests.document(ClipPiecesTests.clipLayer(lengthMS: 8000))
        let id = doc.layers[0].id
        let r23 = doc.addSpeedStop(id, atMS: 500 + 3000)
        let added = try #require(r23)
        #expect(added.stop == 1)
        let r24 = doc.setSpeedStop(id, ofPiece: 0, stop: 1, percent: 400)
        #expect(r24)
        #expect(doc.layer(id: id)?.time?.inMS == 500)
        #expect(doc.layer(id: id)?.time?.outMS == 500 + 3200)
        #expect(doc.layer(id: id)?.motionClockMS(atDocumentTimeMS: 500 + 600) == 1050)
        let r25 = doc.setRampBlend(id, ofPiece: 0, .hold)
        #expect(r25)
        let r26 = doc.resetRamp(id, ofPiece: 0)
        #expect(r26)
        #expect(doc.layer(id: id)?.time?.outMS == 500 + 8000)
        #expect(doc.layer(id: id)?.cuts == nil)
    }

    @Test func aMomentOutsideTheClipTakesNoStop() {
        var doc = ClipPiecesTests.document(ClipPiecesTests.clipLayer(lengthMS: 8000))
        let id = doc.layers[0].id
        let r27 = doc.addSpeedStop(id, atMS: 100)
        #expect(r27 == nil)
        let r28 = doc.addSpeedStop(id, atMS: 9000)
        #expect(r28 == nil)
    }

    @Test func eachStopEditIsOneStepOfUndo() {
        let edits: [(String, (inout PhotonzDocument, UUID) -> Void)] = [
            ("add", { doc, id in _ = doc.addSpeedStop(id, atMS: 3500) }),
            ("speed", { doc, id in _ = doc.setSpeedStop(id, ofPiece: 0, stop: 1, percent: 400) }),
            ("delete", { doc, id in _ = doc.deleteSpeedStop(id, ofPiece: 0, stop: 1) }),
            ("blend", { doc, id in _ = doc.setRampBlend(id, ofPiece: 0, .hold) }),
            ("reset", { doc, id in _ = doc.resetRamp(id, ofPiece: 0) }),
        ]
        for (name, edit) in edits {
            var start = ClipPiecesTests.document(ClipPiecesTests.clipLayer(lengthMS: 8000))
            let id = start.layers[0].id
            if name != "add" { _ = start.addSpeedStop(id, atMS: 3500) }
            var history = History(document: start)
            let was = history.current
            history.perform { doc in edit(&doc, id) }
            #expect(history.current != was, "\(name) changed nothing")
            history.undo()
            #expect(history.current == was, "\(name) took more than one step to undo")
        }
    }

    // MARK: - The words

    @Test func theBlendsAreCalledWhatTheMockCallsThem() {
        #expect(SpeedRampBlend.allCases.map(\.title) == ["Ramp", "Hold"])
    }

    @Test func aRampedPieceIsBadgedAndLinedAsARamp() {
        var doc = ClipPiecesTests.document(ClipPiecesTests.clipLayer(lengthMS: 8000))
        let id = doc.layers[0].id
        _ = doc.addSpeedStop(id, atMS: 3500)
        let line = ClipLine(layer: doc.layers[0], piece: 0)
        #expect(line?.speedText == "ramp")
        #expect(ClipSpeed.rampBadge == "ramp")
    }
}
