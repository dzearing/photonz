import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A hand on a clip's bar in the timeline (`ClipBarDrag`, `docs/design/video-surface.md` §10.4).
///
/// The rules the timeline DRIVES, settled on their own so the view has nothing
/// left to work out. One sentence holds the whole file together:
///
///   **Every edge you can take hold of follows your hand.**
///
/// The bar's left end moves the clip's in point and takes the clip with it;
/// every join, and the bar's right end, is the END of the piece to its left.
/// That is the only arrangement in which nothing you are holding runs away
/// from you, given that a clip's pieces lie end to end with no holes.
@Suite("A clip's bar under a hand")
struct ClipBarDragTests {

    // MARK: - Fixtures

    /// Twenty seconds of recording, of which ten are being played from five
    /// seconds in: there is spare at both ends to pull back out into.
    static func trimmedRecording() -> ClipPieces {
        ClipPieces(single: LayerTime(inMS: 0, outMS: 10_000,
                                     sourceInMS: 5_000, sourceLengthMS: 20_000))
    }

    /// Ten seconds of recording, uncut, with nothing spare either side.
    static func wholeRecording() -> ClipPieces {
        ClipPieces(single: LayerTime(inMS: 0, outMS: 10_000,
                                     sourceInMS: 0, sourceLengthMS: 10_000))
    }

    /// The same ten seconds cut twice: 0–2s, 2s–6s, 6s–10s.
    static func cutTwice() -> ClipPieces {
        var clip = wholeRecording()
        let didFirst = clip.split(atMS: 2000)
        #expect(didFirst)
        let didSecond = clip.split(atMS: 6000)
        #expect(didSecond)
        return clip
    }

    static func ranges(_ clip: ClipPieces) -> [[Int]] {
        (0..<clip.count).map { [clip.rangeMS(ofPiece: $0)!.start, clip.rangeMS(ofPiece: $0)!.end] }
    }

    static func clipLayer(id: UUID = UUID(), startMS: Int = 0,
                          lengthMS: Int = 10_000, sourceLengthMS: Int = 20_000,
                          sourceInMS: Int = 5_000, name: String = "Screen recording") -> Layer {
        var layer = Layer(id: id, name: name,
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#0C0E14")),
                          frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        layer.time = LayerTime(inMS: startMS, outMS: startMS + lengthMS,
                               sourceInMS: sourceInMS, sourceLengthMS: sourceLengthMS)
        return layer
    }

    static func document(_ layers: [Layer], durationMS: Int? = nil) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 160, height: 90))
        doc.layers = layers
        doc.durationMS = durationMS
        return doc
    }

    // MARK: - The bar's left end: the clip's in point

    @Test func theLeftEndDropsFramesAndLeavesTheClipWhereItWasPut() {
        let drag = ClipBarDrag(grab: .clipStart, pieces: Self.trimmedRecording(),
                               clipStartMS: 2_000)
        let landing = drag.landing(byMS: 1_500)
        // The clip still starts where somebody put it, so a recording with the
        // dead air dragged off the front still starts at its own first moment
        // rather than opening on a hole where the dead air used to be.
        #expect(landing.clipStartMS == 2_000)
        #expect(landing.movedMS == 1_500)
        // It is 1.5s shorter, taken off the front, and the bar closed up.
        #expect(landing.pieces.totalLengthMS == 8_500)
        #expect(landing.pieces.piece(at: 0)!.sourceInMS == 6_500)
    }

    @Test func theLeftEndPullsBackOutIntoTheRecordingThatIsStillThere() {
        let drag = ClipBarDrag(grab: .clipStart, pieces: Self.trimmedRecording(),
                               clipStartMS: 6_000)
        let landing = drag.landing(byMS: -2_000)
        #expect(landing.clipStartMS == 6_000)
        #expect(landing.pieces.totalLengthMS == 12_000)
        // It reads two seconds earlier into the recording, which is what
        // "nothing was destroyed" means in numbers.
        #expect(landing.pieces.piece(at: 0)!.sourceInMS == 3_000)
    }

    @Test func theLeftEndStopsWhereTheRecordingRunsOut() {
        // Five seconds of spare in front, and a hand that asks for eight.
        let drag = ClipBarDrag(grab: .clipStart, pieces: Self.trimmedRecording(),
                               clipStartMS: 9_000)
        #expect(drag.limits.least == -5_000)
        let landing = drag.landing(byMS: -8_000)
        #expect(landing.movedMS == -5_000)
        #expect(landing.pieces.piece(at: 0)!.sourceInMS == 0)
    }

    @Test func theLeftEndIsNotStoppedByWhereTheClipSitsInTheDocument() {
        // The clip does not move, so the start of the document has nothing to
        // say about how far back into the recording the edge may go: the five
        // seconds of spare behind the first frame is the whole of it.
        let drag = ClipBarDrag(grab: .clipStart, pieces: Self.trimmedRecording(),
                               clipStartMS: 1_000)
        #expect(drag.limits.least == -5_000)
        let landing = drag.landing(byMS: -4_000)
        #expect(landing.clipStartMS == 1_000)
        #expect(landing.movedMS == -4_000)
    }

    @Test func theLeftEndNeverEatsThePieceItIsOn() {
        let drag = ClipBarDrag(grab: .clipStart, pieces: Self.wholeRecording(),
                               clipStartMS: 0)
        let landing = drag.landing(byMS: 99_000)
        #expect(landing.pieces.totalLengthMS == ClipPiece.shortestMS)
    }

    // MARK: - A join, and the bar's right end

    @Test func aJoinIsTheEndOfThePieceToItsLeftAndFollowsTheHand() {
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.cutTwice(), clipStartMS: 0)
        #expect(drag.grabbedMS == 2_000)
        let landing = drag.landing(byMS: 1_000)
        // The first piece grew by a second, the join went with the hand, and
        // everything after it slid along behind: that is the ripple rule.
        #expect(Self.ranges(landing.pieces) == [[0, 3_000], [3_000, 7_000], [7_000, 11_000]])
    }

    @Test func shorteningAPieceSlidesEverythingAfterItBack() {
        let drag = ClipBarDrag(grab: .seam(after: 1), pieces: Self.cutTwice(), clipStartMS: 0)
        #expect(drag.grabbedMS == 6_000)
        let landing = drag.landing(byMS: -1_500)
        #expect(Self.ranges(landing.pieces) == [[0, 2_000], [2_000, 4_500], [4_500, 8_500]])
        // The clip stayed where it was put. Only its length changed.
        #expect(landing.clipStartMS == 0)
    }

    @Test func theRightEndIsTheLastJoinAndPullsBackOutIntoSpareRecording() {
        // Ten of twenty seconds, read from five in, so five are spare behind.
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.trimmedRecording(),
                               clipStartMS: 0)
        #expect(drag.limits.most == 5_000)
        let landing = drag.landing(byMS: 9_000)
        #expect(landing.pieces.totalLengthMS == 15_000)
        #expect(landing.movedMS == 5_000)
    }

    @Test func aJoinNeverEatsThePieceBehindIt() {
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.cutTwice(), clipStartMS: 0)
        let landing = drag.landing(byMS: -9_000)
        #expect(landing.pieces.piece(at: 0)!.lengthMS == ClipPiece.shortestMS)
    }

    // MARK: - Trimming in and back out again loses nothing

    @Test func aTrimPulledBackOutGivesTheOriginalLengthBack() {
        let original = Self.trimmedRecording()
        let pulledIn = ClipBarDrag(grab: .clipStart, pieces: original, clipStartMS: 5_000)
            .landing(byMS: 3_000)
        #expect(pulledIn.pieces.totalLengthMS == 7_000)
        let pulledBack = ClipBarDrag(grab: .clipStart, pieces: pulledIn.pieces,
                                     clipStartMS: pulledIn.clipStartMS)
            .landing(byMS: -3_000)
        #expect(pulledBack.pieces == original)
        #expect(pulledBack.clipStartMS == 5_000)
        #expect(pulledBack.pieces.piece(at: 0)!.sourceInMS == 5_000)
    }

    // MARK: - The whole clip sliding along

    @Test func theBarSlidesWithoutChangingWhatItPlays() {
        let pieces = Self.cutTwice()
        let drag = ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 1_000)
        let landing = drag.landing(byMS: 2_500)
        #expect(landing.clipStartMS == 3_500)
        #expect(landing.pieces == pieces)
    }

    @Test func theBarCannotSlideBeforeTheFirstFrameOfTheDocument() {
        let drag = ClipBarDrag(grab: .body, pieces: Self.cutTwice(), clipStartMS: 800)
        let landing = drag.landing(byMS: -5_000)
        #expect(landing.clipStartMS == 0)
        #expect(landing.movedMS == -800)
    }

    // MARK: - Catching on what is already there

    @Test func aSlidingBarCatchesOnAnotherClipsEnd() {
        let others = [MotionStripEdge(ms: 4_000, name: "Title", isStart: false)]
        let drag = ClipBarDrag(grab: .body, pieces: Self.cutTwice(), clipStartMS: 0,
                               others: others, snapWithinMS: 200)
        let landing = drag.landing(byMS: 3_900)
        #expect(landing.clipStartMS == 4_000)
        #expect(landing.snappedTo?.name == "Title")
    }

    @Test func aBarOutsideTheCatchingDistanceIsLeftWhereTheHandPutIt() {
        let others = [MotionStripEdge(ms: 4_000, name: "Title", isStart: false)]
        let drag = ClipBarDrag(grab: .body, pieces: Self.cutTwice(), clipStartMS: 0,
                               others: others, snapWithinMS: 200)
        let landing = drag.landing(byMS: 3_500)
        #expect(landing.clipStartMS == 3_500)
        #expect(landing.snappedTo == nil)
    }

    @Test func aJoinCatchesOnThePlayhead() {
        let others = [MotionStripEdge(ms: 7_000, name: ClipBarCopy.thePlayhead, isStart: true)]
        let drag = ClipBarDrag(grab: .seam(after: 1), pieces: Self.cutTwice(), clipStartMS: 0,
                               others: others, snapWithinMS: 250)
        let landing = drag.landing(byMS: 900)
        #expect(landing.snappedTo?.name == ClipBarCopy.thePlayhead)
        #expect(landing.movedMS == 1_000)
    }

    @Test func aCatchTheClipCouldNeverReachIsNotTakenSilently() {
        // The edge could only reach five seconds out; the catch is at nine.
        let others = [MotionStripEdge(ms: 19_000, name: "Title", isStart: true)]
        let drag = ClipBarDrag(grab: .seam(after: 0), pieces: Self.trimmedRecording(),
                               clipStartMS: 0, others: others, snapWithinMS: 2_000)
        let landing = drag.landing(byMS: 8_000)
        #expect(landing.snappedTo == nil)
        #expect(landing.movedMS == 5_000)
    }

    @Test func theEdgesOnOfferAreTheEndsOfTheDocumentThePlayheadAndEveryOtherClip() {
        let a = Self.clipLayer(startMS: 0, lengthMS: 4_000, name: "Shot one")
        var b = Self.clipLayer(startMS: 4_000, lengthMS: 6_000, name: "Shot two")
        var pieces = b.clipPieces!
        let didCut = pieces.split(atMS: 2_000)
        #expect(didCut)
        b.setClipPieces(pieces)
        let doc = Self.document([a, b], durationMS: 10_000)
        let edges = doc.clipBarEdges(excluding: a.id, playheadMS: 3_200)
        #expect(edges.contains { $0.ms == 0 && $0.name == ClipBarCopy.theStart })
        #expect(edges.contains { $0.ms == 10_000 && $0.name == ClipBarCopy.theEnd })
        #expect(edges.contains { $0.ms == 3_200 && $0.name == ClipBarCopy.thePlayhead })
        #expect(edges.contains { $0.ms == 4_000 && $0.name == "Shot two" })
        #expect(edges.contains { $0.ms == 10_000 && $0.name == "Shot two" })
        // The join inside the other clip is an edge too, so a cut lines up
        // with a cut.
        #expect(edges.contains { $0.ms == 6_000 && $0.name == "Shot two" })
        // Its own ends are not on offer: a bar cannot catch on itself.
        #expect(!edges.contains { $0.name == "Shot one" })
    }

    // MARK: - Carrying a piece somewhere else in the order

    @Test func aPieceCarriedNowhereIsNotAMove() {
        let drag = ClipBarDrag(grab: .carry(piece: 1), pieces: Self.cutTwice(), clipStartMS: 0)
        #expect(drag.landing(byMS: 0).dropIndex == nil)
        #expect(drag.landing(byMS: 0).pieces == Self.cutTwice())
    }

    @Test func aPieceCarriedToTheFrontLandsThere() {
        let drag = ClipBarDrag(grab: .carry(piece: 2), pieces: Self.cutTwice(), clipStartMS: 0)
        // Piece three starts at 6s; taken out, the joins left are 0, 2s, 6s.
        let landing = drag.landing(byMS: -6_000)
        #expect(landing.dropIndex == 0)
        #expect(Self.ranges(landing.pieces) == [[0, 4_000], [4_000, 6_000], [6_000, 10_000]])
        // Nothing was lost and nothing was copied: the clip is the same length.
        #expect(landing.pieces.totalLengthMS == 10_000)
    }

    @Test func aPieceCarriedPastOneNeighbourSwapsWithIt() {
        let drag = ClipBarDrag(grab: .carry(piece: 0), pieces: Self.cutTwice(), clipStartMS: 0)
        // Piece one is 2s long; carried 4s right it lands past the piece that
        // is now first, which runs 0–4s.
        let landing = drag.landing(byMS: 4_000)
        #expect(landing.dropIndex == 1)
        #expect(Self.ranges(landing.pieces) == [[0, 4_000], [4_000, 6_000], [6_000, 10_000]])
    }

    @Test func aPieceCarriedOffTheEndLandsLast() {
        let drag = ClipBarDrag(grab: .carry(piece: 0), pieces: Self.cutTwice(), clipStartMS: 0)
        let landing = drag.landing(byMS: 40_000)
        #expect(landing.dropIndex == 2)
        #expect(Self.ranges(landing.pieces) == [[0, 4_000], [4_000, 8_000], [8_000, 10_000]])
    }

    @Test func carryingIsRefusedOnAClipThatIsOnlyOnePiece() {
        let drag = ClipBarDrag(grab: .carry(piece: 0), pieces: Self.wholeRecording(), clipStartMS: 0)
        #expect(drag.landing(byMS: 5_000).dropIndex == nil)
    }

    // MARK: - Landing one on a document

    @Test func draggingTheInPointIsOneStepAndLeavesNoHoleAtTheFront() {
        let layer = Self.clipLayer(startMS: 0)
        var doc = Self.document([layer], durationMS: 10_000)
        let didTrim = doc.trimClipStart(layer.id, ofPiece: 0, byMS: 2_000)
        #expect(didTrim)
        let time = doc.layer(id: layer.id)!.time!
        // The recording still starts at its own first moment...
        #expect(time.inMS == 0)
        #expect(time.outMS == 8_000)
        // ...and the ruler followed, so the transport counts to eight.
        #expect(doc.documentDurationMS == 8_000)
    }

    @Test func aClipSlidesAndTheDocumentGrowsToHoldIt() {
        let layer = Self.clipLayer(startMS: 0)
        var doc = Self.document([layer], durationMS: 10_000)
        let didMove = doc.moveClip(layer.id, toInMS: 2_500)
        #expect(didMove)
        #expect(doc.layer(id: layer.id)!.time!.inMS == 2_500)
        #expect(doc.documentDurationMS == 12_500)
    }

    @Test func aClipCannotSlideBeforeTheFirstFrame() {
        let layer = Self.clipLayer(startMS: 0)
        var doc = Self.document([layer], durationMS: 10_000)
        let didMove = doc.moveClip(layer.id, toInMS: -500)
        #expect(!didMove)
    }

    @Test func throwingAPieceAwayShortensTheDocumentToMatch() {
        var layer = Self.clipLayer(startMS: 0, lengthMS: 10_000, sourceLengthMS: 10_000, sourceInMS: 0)
        var pieces = layer.clipPieces!
        let didCut = pieces.split(atMS: 6_000)
        #expect(didCut)
        layer.setClipPieces(pieces)
        var doc = Self.document([layer], durationMS: 10_000)
        let didRemove = doc.removeClipPiece(layer.id, at: 1)
        #expect(didRemove)
        #expect(doc.layer(id: layer.id)!.time!.outMS == 6_000)
        // The one that used to be missed: the ruler and the transport said ten
        // seconds long after the last four had been thrown away.
        #expect(doc.documentDurationMS == 6_000)
    }

    // MARK: - What the capsule says

    @Test func theCapsuleSaysThePieceItsLengthAndWhatTheDragChanged() {
        #expect(ClipBarCopy.trimming(pieceNumber: 2, of: 3, lengthMS: 3_400, changeMS: -1_400)
                == "Piece 2 · 3.4s · -1.4s")
        // One piece is just a clip, so there is no piece number to say.
        #expect(ClipBarCopy.trimming(pieceNumber: 1, of: 1, lengthMS: 8_000, changeMS: 500)
                == "8.0s · +0.5s")
    }

    @Test func aDragThatHasNotMovedSaysSo() {
        #expect(ClipBarCopy.change(0) == "0.0s")
    }

    @Test func slidingSaysWhereItWouldStart() {
        #expect(ClipBarCopy.moving(startMS: 63_000, changeMS: 1_000) == "Starts 1:03 · +1.0s")
    }

    @Test func carryingSaysWhereItIsGoing() {
        #expect(ClipBarCopy.carrying(pieceNumber: 3, toPlace: 1, of: 3)
                == "Piece 3 → place 1 of 3")
    }
}
