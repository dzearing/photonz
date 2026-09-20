import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A clip cut into pieces: the rules for splitting a take, throwing a piece
/// away, putting the pieces in another order, trimming without losing
/// anything, holding on a frame and speeding a stretch up
/// (`docs/design/video-surface.md` §2, UX-PATTERNS D18).
///
/// Written before the model, which is the rule for `PhotonzCore`. Nothing here
/// has heard of a timeline, a gesture or a player: these are the rules the
/// timeline will DRIVE, settled and proved on their own so the surface that
/// shows them has nothing left to work out.
///
/// The one sentence the whole file keeps saying: **a split adds a piece to a
/// clip, never a second clip**, and the pieces of a clip are laid back to back
/// with no gap anywhere, so there is never a hole to drag shut.
@Suite("A clip in pieces")
struct ClipPiecesTests {

    // MARK: - Fixtures

    /// Ten seconds of recording, uncut: one piece reading the whole file.
    static func recording(lengthMS: Int = 10_000) -> ClipPieces {
        ClipPieces(single: LayerTime(inMS: 0, outMS: lengthMS,
                                     sourceInMS: 0, sourceLengthMS: lengthMS))
    }

    /// The same recording cut twice: 0–2s, 2s–6s, 6s–10s.
    static func cutTwice() -> ClipPieces {
        var clip = recording()
        let did1 = clip.split(atMS: 2000)
        #expect(did1)
        let did2 = clip.split(atMS: 6000)
        #expect(did2)
        return clip
    }

    /// A layer that is a clip: it occupies time and reads a recording.
    static func clipLayer(lengthMS: Int = 10_000) -> Layer {
        var layer = Layer(name: "Screen recording",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#0C0E14")),
                          frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        layer.time = LayerTime(inMS: 500, outMS: 500 + lengthMS,
                               sourceInMS: 0, sourceLengthMS: lengthMS)
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 160, height: 90))
        doc.layers = [layer]
        return doc
    }

    /// Where every piece starts and ends, for reading a whole clip at a glance.
    static func ranges(_ clip: ClipPieces) -> [[Int]] {
        (0..<clip.count).map { [clip.rangeMS(ofPiece: $0)!.start, clip.rangeMS(ofPiece: $0)!.end] }
    }

    // MARK: - A clip splits into pieces

    @Test func aCutMakesTwoPiecesThatMeetWhereItLanded() {
        var clip = Self.recording()
        #expect(clip.count == 1)
        let did3 = clip.split(atMS: 4000)
        #expect(did3)
        #expect(clip.count == 2)
        #expect(Self.ranges(clip) == [[0, 4000], [4000, 10_000]])
        // Nothing was lost: the two together are exactly what the one was.
        #expect(clip.totalLengthMS == 10_000)
    }

    @Test func bothPiecesStillReadTheSameRecording() {
        var clip = Self.recording()
        let did4 = clip.split(atMS: 4000)
        #expect(did4)
        #expect(clip.piece(at: 0)!.sourceOutMS == clip.piece(at: 1)!.sourceInMS)
        #expect(clip.piece(at: 1)!.sourceInMS == 4000)
        #expect(clip.sourceLengthMS == 10_000)
        // The frame that plays at a moment is the frame that played there
        // before the cut.
        #expect(clip.sourceMS(atMS: 7500) == 7500)
    }

    @Test func eitherPieceCanBeCutAgain() {
        var clip = Self.recording()
        let did5 = clip.split(atMS: 4000)
        #expect(did5)
        let did6 = clip.split(atMS: 2000)          // inside the first
        #expect(did6)
        let did7 = clip.split(atMS: 7000)          // inside the last
        #expect(did7)
        #expect(Self.ranges(clip) == [[0, 2000], [2000, 4000], [4000, 7000], [7000, 10_000]])
        #expect(clip.totalLengthMS == 10_000)
    }

    @Test func aCutOnTopOfACutIsRefusedAndChangesNothing() {
        var clip = Self.recording()
        let did8 = clip.split(atMS: 4000)
        #expect(did8)
        let before = clip
        let did9 = clip.split(atMS: 4000)
        #expect(did9 == false)
        #expect(clip == before)
    }

    @Test func aCutTooCloseToAnEdgeIsRefused() {
        var clip = Self.recording()
        let did10 = clip.split(atMS: 0)
        #expect(did10 == false)
        let did11 = clip.split(atMS: ClipPiece.shortestMS - 1)
        #expect(did11 == false)
        let did12 = clip.split(atMS: 10_000)
        #expect(did12 == false)
        let did13 = clip.split(atMS: 10_000 - ClipPiece.shortestMS + 1)
        #expect(did13 == false)
        #expect(clip.count == 1)
        // ...and exactly a shortest piece either side is allowed.
        let did14 = clip.split(atMS: ClipPiece.shortestMS)
        #expect(did14)
    }

    @Test func cuttingCopiesNoFrames() {
        var clip = Self.recording()
        let did15 = clip.split(atMS: 4000)
        #expect(did15)
        let did16 = clip.split(atMS: 1000)
        #expect(did16)
        // Every piece is still a window on the one file, and together they
        // still cover exactly the stretch the uncut clip covered.
        #expect(clip.playback.map(\.sourceInMS) == [0, 1000, 4000])
        #expect(clip.playback.map(\.sourceLengthMS) == [1000, 3000, 6000])
    }

    // MARK: - The pieces can be put in another order

    @Test func aPieceCanBePutSomewhereElse() {
        var clip = Self.cutTwice()
        #expect(clip.playback.map(\.sourceInMS) == [0, 2000, 6000])
        let did17 = clip.move(from: 2, to: 0)
        #expect(did17)
        #expect(clip.playback.map(\.sourceInMS) == [6000, 0, 2000])
        // Reordering is not retiming: the clip is exactly as long as it was.
        #expect(clip.totalLengthMS == 10_000)
    }

    @Test func whatPlaysFollowsTheNewOrder() {
        var clip = Self.cutTwice()
        let did18 = clip.move(from: 2, to: 0)
        #expect(did18)
        // The last four seconds of the recording now play first.
        #expect(Self.ranges(clip) == [[0, 4000], [4000, 6000], [6000, 10_000]])
        #expect(clip.sourceMS(atMS: 0) == 6000)
        #expect(clip.sourceMS(atMS: 4000) == 0)
    }

    @Test func whatAnExportWouldWriteFollowsTheNewOrderToo() {
        var clip = Self.cutTwice()
        let did19 = clip.move(from: 0, to: 2)
        #expect(did19)
        let written = clip.playback
        #expect(written.map(\.startMS) == [0, 4000, 8000])
        #expect(written.map(\.sourceInMS) == [2000, 6000, 0])
        #expect(written.map(\.sourceLengthMS) == [4000, 4000, 2000])
        // Nothing else to change: the pieces are still laid back to back.
        #expect(written.map(\.lengthMS).reduce(0, +) == clip.totalLengthMS)
    }

    @Test func movingAPieceNowhereOrOffTheEndIsRefused() {
        var clip = Self.cutTwice()
        let before = clip
        let did20 = clip.move(from: 1, to: 1)
        #expect(did20 == false)
        let did21 = clip.move(from: 3, to: 0)
        #expect(did21 == false)
        let did22 = clip.move(from: 0, to: 9)
        #expect(did22 == false)
        #expect(clip == before)
    }

    // MARK: - The gap a piece leaves

    @Test func takingAPieceOutClosesTheGapItLeaves() {
        var clip = Self.cutTwice()
        let did23 = clip.remove(at: 1)                    // the four seconds in the middle
        #expect(did23)
        #expect(clip.count == 2)
        // Everything after it slides up: there is no hole, and none to drag shut.
        #expect(Self.ranges(clip) == [[0, 2000], [2000, 6000]])
        #expect(clip.totalLengthMS == 6000)
        #expect(clip.sourceMS(atMS: 2000) == 6000)
    }

    @Test func theSameRuleHoldsWhenAPieceIsMadeLonger() {
        var clip = Self.cutTwice()
        // The first piece's end pulled out by half a second.
        let did24 = clip.trimEnd(ofPiece: 0, byMS: 500)
        #expect(did24)
        // Everything after it moves along by exactly that, and nothing overlaps.
        #expect(Self.ranges(clip) == [[0, 2500], [2500, 6500], [6500, 10_500]])
        #expect(clip.totalLengthMS == 10_500)
    }

    @Test func theLastPieceOfAClipCannotBeTakenOut() {
        var clip = Self.recording()
        #expect(clip.canRemove(at: 0) == false)
        let did25 = clip.remove(at: 0)
        #expect(did25 == false)
        #expect(clip.count == 1)
    }

    @Test func thereIsNeverAHoleBetweenTwoPieces() {
        var clip = Self.recording()
        let did26 = clip.split(atMS: 2000)
        #expect(did26)
        let did27 = clip.split(atMS: 6000)
        #expect(did27)
        let did28 = clip.move(from: 2, to: 0)
        #expect(did28)
        let did29 = clip.remove(at: 1)
        #expect(did29)
        let did30 = clip.setSpeed(ofPiece: 1, percent: 200)
        #expect(did30)
        let did31 = clip.holdFrame(atMS: 1000, forMS: 700)
        #expect(did31)
        var cursor = 0
        for index in 0..<clip.count {
            let range = clip.rangeMS(ofPiece: index)!
            #expect(range.start == cursor)
            cursor = range.end
        }
        #expect(cursor == clip.totalLengthMS)
    }

    // MARK: - Trimming never destroys anything

    @Test func aPiecePulledInAndBackOutIsExactlyWhatItWas() {
        var clip = Self.cutTwice()
        let before = clip
        let did32 = clip.trimStart(ofPiece: 1, byMS: 400)
        #expect(did32)
        #expect(clip != before)
        let did33 = clip.trimStart(ofPiece: 1, byMS: -400)
        #expect(did33)
        #expect(clip == before)
    }

    @Test func aPiecePulledInAndBackOutAtAnotherSpeedIsExactlyWhatItWasToo() {
        var clip = Self.cutTwice()
        let did34 = clip.setSpeed(ofPiece: 1, percent: 150)
        #expect(did34)
        let before = clip
        let did35 = clip.trimStart(ofPiece: 1, byMS: 333)
        #expect(did35)
        #expect(clip != before)
        let did36 = clip.trimStart(ofPiece: 1, byMS: -333)
        #expect(did36)
        #expect(clip == before)
    }

    @Test func aPieceShortenedAtTheEndAndPulledBackOutIsWhatItWas() {
        var clip = Self.cutTwice()
        let before = clip
        let did37 = clip.trimEnd(ofPiece: 1, byMS: -1750)
        #expect(did37)
        #expect(clip != before)
        let did38 = clip.trimEnd(ofPiece: 1, byMS: 1750)
        #expect(did38)
        #expect(clip == before)
    }

    @Test func trimmingTheHeadLeavesEveryOtherFrameWhereItWas() {
        var clip = Self.recording()
        let did39 = clip.trimStart(ofPiece: 0, byMS: 1500)
        #expect(did39)
        // A moment that was at 4s is now at 2.5s, and it is the same frame.
        #expect(clip.sourceMS(atMS: 2500) == 4000)
        #expect(clip.totalLengthMS == 8500)
    }

    @Test func aTrimStopsAtTheEndsOfTheRecording() {
        var clip = Self.recording()
        // There is nothing before the first frame to pull out into...
        let did40 = clip.trimStart(ofPiece: 0, byMS: -3000)
        #expect(did40 == false)
        // ...nor anything after the last.
        let did41 = clip.trimEnd(ofPiece: 0, byMS: 3000)
        #expect(did41 == false)
        #expect(clip.totalLengthMS == 10_000)
        // Once a head has been pulled in, that much can be pulled back out.
        let did42 = clip.trimStart(ofPiece: 0, byMS: 2000)
        #expect(did42)
        let did43 = clip.trimStart(ofPiece: 0, byMS: -2000)
        #expect(did43)
        #expect(clip.piece(at: 0)!.sourceInMS == 0)
    }

    @Test func aPieceCannotBeTrimmedAwayAltogether() {
        var clip = Self.cutTwice()
        let did44 = clip.trimEnd(ofPiece: 1, byMS: -4000)
        #expect(did44 == false)
        #expect(clip.piece(at: 1)!.lengthMS == 4000)
        // ...and a piece may be trimmed down to the shortest there is.
        let did45 = clip.trimEnd(ofPiece: 1, byMS: -(4000 - ClipPiece.shortestMS))
        #expect(did45)
        #expect(clip.piece(at: 1)!.lengthMS == ClipPiece.shortestMS)
    }

    @Test func aTrimSaysHowFarItCanGoBeforeItIsAsked() {
        var clip = Self.cutTwice()
        // The middle piece: two seconds of recording behind it, four in it.
        let start = clip.trimStartRange(ofPiece: 1)!
        #expect(start.out == -2000)
        #expect(start.in == 4000 - ClipPiece.shortestMS)
        let end = clip.trimEndRange(ofPiece: 1)!
        #expect(end.in == -(4000 - ClipPiece.shortestMS))
        #expect(end.out == 4000)               // the last four seconds of the file
        // What it says is exactly what the edit allows, at both walls.
        let didFurthest = clip.trimEnd(ofPiece: 1, byMS: end.out!)
        #expect(didFurthest)
        let didTooFar = clip.trimEnd(ofPiece: 1, byMS: 1)
        #expect(didTooFar == false)
    }

    @Test func nothingStopsAHeldFrameBeingHeldLonger() {
        var clip = Self.recording()
        let didHold = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(didHold)
        #expect(clip.trimStartRange(ofPiece: 1)!.out == nil)
        #expect(clip.trimEndRange(ofPiece: 1)!.out == nil)
        let didStretch = clip.trimEnd(ofPiece: 1, byMS: 600_000)
        #expect(didStretch)
        #expect(clip.piece(at: 1)!.lengthMS == 602_000)
    }

    // MARK: - A held frame

    @Test func aHeldFrameStartsAndEndsAtTheSameMoment() {
        let held = ClipPiece.held(atSourceMS: 4000, forMS: 2000)
        #expect(held.sourceInMS == 4000)
        #expect(held.sourceOutMS == 4000)
        #expect(held.isHeld)
        #expect(held.lengthMS == 2000)
    }

    @Test func aHeldFrameTakesItsPlaceLikeAnyOtherPiece() {
        var clip = Self.recording()
        let did46 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did46)
        #expect(Self.ranges(clip) == [[0, 4000], [4000, 6000], [6000, 12_000]])
        // The frame held is the one the playhead was on, and the recording
        // picks up exactly where it left off.
        #expect(clip.sourceMS(atMS: 5000) == 4000)
        #expect(clip.sourceMS(atMS: 6000) == 4000)
        #expect(clip.sourceMS(atMS: 6500) == 4500)
    }

    @Test func aHeldFrameIsMovedAndTakenOutLikeAnyOtherPiece() {
        var clip = Self.recording()
        let did47 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did47)
        let did48 = clip.move(from: 1, to: 0)
        #expect(did48)
        #expect(clip.piece(at: 0)!.isHeld)
        #expect(clip.rangeMS(ofPiece: 0)! == (start: 0, end: 2000))
        let did49 = clip.remove(at: 0)
        #expect(did49)
        #expect(clip.count == 2)
        #expect(clip.totalLengthMS == 10_000)
    }

    @Test func aHeldFrameIsMadeLongerAndShorterLikeAnyOtherPiece() {
        var clip = Self.recording()
        let did50 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did50)
        let before = clip
        let did51 = clip.trimEnd(ofPiece: 1, byMS: -1000)
        #expect(did51)
        #expect(clip.piece(at: 1)!.lengthMS == 1000)
        #expect(clip.piece(at: 1)!.sourceInMS == 4000)     // still the same frame
        let did52 = clip.trimEnd(ofPiece: 1, byMS: 1000)
        #expect(did52)
        #expect(clip == before)
    }

    @Test func aHeldFrameSplitsIntoTwoOfTheSameFrame() {
        var clip = Self.recording()
        let did53 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did53)
        let did54 = clip.split(atMS: 5000)
        #expect(did54)
        #expect(clip.piece(at: 1)!.isHeld)
        #expect(clip.piece(at: 2)!.isHeld)
        #expect(clip.piece(at: 1)!.sourceInMS == 4000)
        #expect(clip.piece(at: 2)!.sourceInMS == 4000)
        #expect(clip.totalLengthMS == 12_000)
    }

    @Test func aHeldFrameHasNoSound() {
        let held = ClipPiece.held(atSourceMS: 4000, forMS: 2000)
        #expect(held.playsSound == false)
        #expect(ClipPiece(sourceInMS: 0, lengthMS: 1000).playsSound)
    }

    @Test func anExportWritesAHeldFrameAsOneFrameHeld() {
        var clip = Self.recording()
        let did55 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did55)
        let written = clip.playback[1]
        #expect(written.isHeld)
        #expect(written.sourceInMS == 4000)
        #expect(written.sourceLengthMS == 0)          // no recording runs under it
        #expect(written.lengthMS == 2000)             // it is on screen for two seconds
        #expect(written.playsSound == false)
    }

    // MARK: - A piece can be given a speed

    @Test func atDoubleSpeedAPieceIsHalfAsLong() {
        var clip = Self.cutTwice()
        let did56 = clip.setSpeed(ofPiece: 1, percent: 200)
        #expect(did56)
        #expect(clip.piece(at: 1)!.lengthMS == 2000)
        #expect(clip.totalLengthMS == 8000)
        // It still reads the same four seconds of the recording.
        #expect(clip.piece(at: 1)!.sourceInMS == 2000)
        #expect(clip.piece(at: 1)!.sourceOutMS == 6000)
    }

    @Test func atHalfSpeedAPieceIsTwiceAsLong() {
        var clip = Self.cutTwice()
        let did57 = clip.setSpeed(ofPiece: 1, percent: 50)
        #expect(did57)
        #expect(clip.piece(at: 1)!.lengthMS == 8000)
        #expect(clip.piece(at: 1)!.sourceOutMS == 6000)
        // And everything after it moves along, by the one gap rule.
        #expect(Self.ranges(clip) == [[0, 2000], [2000, 10_000], [10_000, 14_000]])
    }

    @Test func theSoundGoesWithThePicture() {
        var clip = Self.cutTwice()
        #expect(clip.piece(at: 1)!.soundRatePercent == 100)
        let did58 = clip.setSpeed(ofPiece: 1, percent: 200)
        #expect(did58)
        // The sound plays at the speed the picture does, so it rises in pitch.
        // Nothing in the model corrects it; a control that does is a later task.
        #expect(clip.piece(at: 1)!.soundRatePercent == 200)
        #expect(clip.piece(at: 1)!.playsSound)
    }

    @Test func aSpeedThereAndBackLeavesTheRecordingWhereItWas() {
        var clip = Self.cutTwice()
        let source = (clip.piece(at: 1)!.sourceInMS, clip.piece(at: 1)!.sourceOutMS)
        let did59 = clip.setSpeed(ofPiece: 1, percent: 250)
        #expect(did59)
        let did60 = clip.setSpeed(ofPiece: 1, percent: 100)
        #expect(did60)
        #expect(clip.piece(at: 1)!.sourceInMS == source.0)
        #expect(clip.piece(at: 1)!.sourceOutMS == source.1)
        #expect(clip.piece(at: 1)!.speedPercent == 100)
    }

    @Test func aSpeedOutsideWhatThePlayerCanDoIsBroughtBackInside() {
        var clip = Self.recording()
        let did61 = clip.setSpeed(ofPiece: 0, percent: 9000)
        #expect(did61)
        #expect(clip.piece(at: 0)!.speedPercent == ClipPiece.fastestPercent)
        let did62 = clip.setSpeed(ofPiece: 0, percent: 1)
        #expect(did62)
        #expect(clip.piece(at: 0)!.speedPercent == ClipPiece.slowestPercent)
        // Nought is not a speed: a frame held is made by holding a frame.
        let did63 = clip.setSpeed(ofPiece: 0, percent: 0)
        #expect(did63 == false)
        #expect(clip.piece(at: 0)!.isHeld == false)
    }

    @Test func aHeldFrameHasNoSpeedToGive() {
        var clip = Self.recording()
        let did64 = clip.holdFrame(atMS: 4000, forMS: 2000)
        #expect(did64)
        let before = clip
        let did65 = clip.setSpeed(ofPiece: 1, percent: 200)
        #expect(did65 == false)
        #expect(clip == before)
    }

    // MARK: - A clip, a layer, and one step of undo

    @Test func aLayerWithNoTimeHasNoPieces() {
        let layer = Layer(name: "Background",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#0C0E14")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(layer.clipPieces == nil)
    }

    @Test func aClipWithNoCutsReadsAsOnePiece() {
        let layer = Self.clipLayer()
        let pieces = layer.clipPieces!
        #expect(pieces.count == 1)
        #expect(pieces.totalLengthMS == 10_000)
        #expect(pieces.sourceLengthMS == 10_000)
        #expect(pieces.isOnePlainPiece)
    }

    @Test func thePieceListAndTheLayersStretchNeverDisagree() {
        var doc = Self.document(Self.clipLayer())
        let id = doc.layers[0].id
        let did66 = doc.splitClip(id, atMS: 4500)          // document time: the clip starts at 500
        #expect(did66)
        let did67 = doc.removeClipPiece(id, at: 0)
        #expect(did67)
        let layer = doc.layer(id: id)!
        #expect(layer.time!.inMS == 500)                // the clip stays where it is...
        #expect(layer.time!.lengthMS == layer.clipPieces!.totalLengthMS)
        #expect(layer.time!.outMS == 500 + 6000)        // ...and shortens from the end
        #expect(layer.time!.sourceInMS == layer.clipPieces!.piece(at: 0)!.sourceInMS)
    }

    @Test func aCutIsMadeAtTheMomentOnTheDocumentsOwnClock() {
        var doc = Self.document(Self.clipLayer())
        let id = doc.layers[0].id
        let did68 = doc.splitClip(id, atMS: 4500)
        #expect(did68)
        let pieces = doc.layer(id: id)!.clipPieces!
        #expect(pieces.count == 2)
        #expect(pieces.piece(at: 0)!.lengthMS == 4000)
        #expect(pieces.piece(at: 1)!.sourceInMS == 4000)
        // A moment outside the clip is not a moment in it.
        let did69 = doc.splitClip(id, atMS: 200)
        #expect(did69 == false)
        let did70 = doc.splitClip(id, atMS: 99_000)
        #expect(did70 == false)
    }

    @Test func eachOfTheseIsOneStepOfUndo() {
        let edits: [(String, (inout PhotonzDocument, UUID) -> Bool)] = [
            ("split", { doc, id in doc.splitClip(id, atMS: 4500) }),
            ("remove", { doc, id in
                _ = doc.splitClip(id, atMS: 4500)
                return doc.removeClipPiece(id, at: 0)
            }),
            ("reorder", { doc, id in
                _ = doc.splitClip(id, atMS: 4500)
                return doc.moveClipPiece(id, from: 1, to: 0)
            }),
            ("trim", { doc, id in doc.trimClipStart(id, ofPiece: 0, byMS: 2000) }),
            ("hold", { doc, id in doc.holdFrame(id, atMS: 4500, forMS: 2000) }),
            ("speed", { doc, id in doc.setClipSpeed(id, ofPiece: 0, percent: 200) }),
        ]
        for (name, edit) in edits {
            let start = Self.document(Self.clipLayer())
            let id = start.layers[0].id
            var history = History(document: start)
            let was = history.current
            history.perform { doc in _ = edit(&doc, id) }
            #expect(history.current != was, "\(name) changed nothing")
            #expect(history.canUndo, "\(name) recorded no step")
            history.undo()
            #expect(history.current == was, "\(name) took more than one step to undo")
            #expect(history.canUndo == false, "\(name) left a second step on the stack")
        }
    }

    @Test func aDuplicateOfACutClipIsStillCut() {
        var doc = Self.document(Self.clipLayer())
        let id = doc.layers[0].id
        let did71 = doc.splitClip(id, atMS: 4500)
        #expect(did71)
        let copy = doc.layer(id: id)!.duplicated()
        #expect(copy.clipPieces!.count == 2)
        #expect(copy.clipPieces == doc.layer(id: id)!.clipPieces)
    }

    // MARK: - Nothing changes for anything that exists today

    @Test func anUncutClipWritesNothingExtra() throws {
        let layer = Self.clipLayer()
        let written = try JSONEncoder().encode(layer)
        let text = String(decoding: written, as: UTF8.self)
        #expect(text.contains("\"cuts\"") == false)
        let read = try JSONDecoder().decode(Layer.self, from: written)
        #expect(read.clipPieces == layer.clipPieces)
    }

    @Test func aCutClipSurvivesBeingWrittenDownAndReadBack() throws {
        var doc = Self.document(Self.clipLayer())
        let id = doc.layers[0].id
        let did72 = doc.splitClip(id, atMS: 4500)
        #expect(did72)
        let did73 = doc.setClipSpeed(id, ofPiece: 1, percent: 200)
        #expect(did73)
        let did74 = doc.holdFrame(id, atMS: 2500, forMS: 1500)
        #expect(did74)
        let written = try JSONEncoder().encode(doc.layers[0])
        let read = try JSONDecoder().decode(Layer.self, from: written)
        #expect(read.clipPieces == doc.layers[0].clipPieces)
        #expect(read.time == doc.layers[0].time)
    }

    @Test func aClipCutBackToOnePlainPieceIsAnOrdinaryStretchAgain() {
        var doc = Self.document(Self.clipLayer())
        let id = doc.layers[0].id
        let did75 = doc.splitClip(id, atMS: 4500)
        #expect(did75)
        let did76 = doc.removeClipPiece(id, at: 1)
        #expect(did76)
        #expect(doc.layer(id: id)!.clipPieces!.isOnePlainPiece)
        #expect(doc.layer(id: id)!.cuts == nil)
    }

    // MARK: - A recording already cut arrives in the same shape

    @Test func aRecordingCutInTheRecordingWindowArrivesAsTheSamePieces() {
        var cuts = VideoCutList(duration: 10)
        let didCut1 = cuts.split(atTimeline: 2)
        #expect(didCut1)
        let didCut2 = cuts.split(atTimeline: 6)
        #expect(didCut2)
        let didDrop = cuts.removePiece(at: 1)
        #expect(didDrop)
        let clip = ClipPieces(cutList: cuts)
        #expect(clip.count == 2)
        #expect(clip.playback.map(\.sourceInMS) == [0, 6000])
        #expect(clip.playback.map(\.lengthMS) == [2000, 4000])
        #expect(clip.totalLengthMS == 6000)
        #expect(clip.sourceLengthMS == 10_000)
        // The stretches it projects are the ones the document model already
        // knew how to read (`DocumentTime.swift`).
        #expect(clip.playback.map(\.lengthMS) == cuts.layerTimes().map(\.lengthMS))
    }
}
