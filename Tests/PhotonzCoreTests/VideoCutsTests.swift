import Testing
import Foundation
@testable import PhotonzCore

@Suite("Video cut list")
struct VideoCutsTests {

    // MARK: - Starting state

    @Test("A fresh recording is one piece covering the whole clip")
    func freshIsOnePiece() {
        let cuts = VideoCutList(duration: 18)
        #expect(cuts.pieces.count == 1)
        #expect(cuts.pieces[0].start == 0)
        #expect(cuts.pieces[0].end == 18)
        #expect(cuts.timelineDuration == 18)
        #expect(cuts.isWholeClip)
        #expect(!cuts.isCut)
    }

    @Test("A negative duration still yields one valid piece")
    func negativeDuration() {
        let cuts = VideoCutList(duration: -5)
        #expect(cuts.pieces.count == 1)
        #expect(cuts.sourceDuration == 0)
        #expect(cuts.timelineDuration == 0)
    }

    // MARK: - Splitting

    @Test("Splitting in the middle gives two pieces that meet at the cut")
    func splitMakesTwoPieces() {
        var cuts = VideoCutList(duration: 18)
        let did1 = cuts.split(atTimeline: 7)
        #expect(did1)
        #expect(cuts.pieces.count == 2)
        #expect(cuts.pieces[0].start == 0)
        #expect(cuts.pieces[0].end == 7)
        #expect(cuts.pieces[1].start == 7)
        #expect(cuts.pieces[1].end == 18)
        // Cutting never loses time.
        #expect(cuts.timelineDuration == 18)
        #expect(cuts.isCut)
        #expect(!cuts.isWholeClip)
    }

    @Test("Splitting twice gives three pieces in order")
    func splitTwice() {
        var cuts = VideoCutList(duration: 18)
        let did2 = cuts.split(atTimeline: 7)
        #expect(did2)
        let did3 = cuts.split(atTimeline: 12)
        #expect(did3)
        #expect(cuts.pieces.count == 3)
        #expect(cuts.pieces.map(\.start) == [0, 7, 12])
        #expect(cuts.pieces.map(\.end) == [7, 12, 18])
        #expect(cuts.timelineDuration == 18)
    }

    @Test("Splitting at either end, or on an existing cut, is refused")
    func splitAtBoundaryRefused() {
        var cuts = VideoCutList(duration: 18)
        let did4 = cuts.split(atTimeline: 0)
        #expect(!did4)
        let did5 = cuts.split(atTimeline: 18)
        #expect(!did5)
        let did6 = cuts.split(atTimeline: 0.02)
        #expect(!did6)  // inside the minimum piece
        #expect(cuts.pieces.count == 1)

        let did7 = cuts.split(atTimeline: 7)
        #expect(did7)
        let did8 = cuts.split(atTimeline: 7)
        #expect(!did8)     // already a cut there
        #expect(cuts.pieces.count == 2)
    }

    @Test("canSplit agrees with split")
    func canSplitAgrees() {
        var cuts = VideoCutList(duration: 18)
        #expect(cuts.canSplit(atTimeline: 7))
        #expect(!cuts.canSplit(atTimeline: 0))
        #expect(!cuts.canSplit(atTimeline: 18))
        _ = cuts.split(atTimeline: 7)
        #expect(!cuts.canSplit(atTimeline: 7))
        #expect(cuts.canSplit(atTimeline: 3))
    }

    // MARK: - Dropping a piece

    @Test("Removing the first piece leaves the rest starting at zero on the timeline")
    func removeFirstPiece() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        let did9 = cuts.removePiece(at: 0)
        #expect(did9)
        #expect(cuts.pieces.count == 1)
        // The kept piece still reads source 7...18, but plays from 0.
        #expect(cuts.pieces[0].start == 7)
        #expect(cuts.pieces[0].end == 18)
        #expect(cuts.timelineDuration == 11)
        #expect(cuts.timelineStart(ofPiece: 0) == 0)
    }

    @Test("Removing a middle piece closes the gap with no hole left behind")
    func removeMiddlePiece() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.split(atTimeline: 12)
        let did10 = cuts.removePiece(at: 1)
        #expect(did10)
        #expect(cuts.pieces.count == 2)
        #expect(cuts.timelineDuration == 13)
        // Piece 2 now begins where piece 1 ends: nothing plays in between.
        #expect(cuts.timelineStart(ofPiece: 0) == 0)
        #expect(cuts.timelineStart(ofPiece: 1) == 7)
    }

    @Test("The last remaining piece cannot be removed")
    func cannotEmptyTheRecording() {
        var cuts = VideoCutList(duration: 18)
        #expect(!cuts.canRemovePiece(at: 0))
        let did11 = cuts.removePiece(at: 0)
        #expect(!did11)
        #expect(cuts.pieces.count == 1)
    }

    @Test("Removing an out-of-range piece is refused")
    func removeOutOfRange() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        let did12 = cuts.removePiece(at: 5)
        #expect(!did12)
        let did13 = cuts.removePiece(at: -1)
        #expect(!did13)
        #expect(cuts.pieces.count == 2)
    }

    // MARK: - Timeline ↔ source mapping

    @Test("Timeline time maps into the source across a dropped piece")
    func timelineMapsAcrossACut() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.split(atTimeline: 12)
        _ = cuts.removePiece(at: 1)  // drop source 7...12

        // Before the join, timeline time is source time.
        #expect(cuts.sourceTime(forTimeline: 3) == 3)
        // At the join, it jumps over the dropped five seconds.
        #expect(cuts.sourceTime(forTimeline: 7) == 12)
        #expect(cuts.sourceTime(forTimeline: 9) == 14)
        // Past the end it clamps.
        #expect(cuts.sourceTime(forTimeline: 100) == 18)
        #expect(cuts.sourceTime(forTimeline: -3) == 0)
    }

    @Test("The piece under the playhead is the one the time falls in")
    func pieceAtTimeline() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        #expect(cuts.pieceIndex(atTimeline: 0) == 0)
        #expect(cuts.pieceIndex(atTimeline: 3) == 0)
        #expect(cuts.pieceIndex(atTimeline: 6.99) == 0)
        // Exactly on the cut belongs to the piece that starts there.
        #expect(cuts.pieceIndex(atTimeline: 7) == 1)
        #expect(cuts.pieceIndex(atTimeline: 17) == 1)
        // The very end belongs to the last piece rather than to nothing.
        #expect(cuts.pieceIndex(atTimeline: 18) == 1)
    }

    @Test("A piece reports where it sits on the timeline")
    func timelineRangeOfPiece() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        let first = cuts.timelineRange(ofPiece: 0)
        let second = cuts.timelineRange(ofPiece: 1)
        #expect(first?.start == 0)
        #expect(first?.end == 7)
        #expect(second?.start == 7)
        #expect(second?.end == 18)
        #expect(cuts.timelineRange(ofPiece: 9) == nil)
    }

    // MARK: - Trimming on top of cuts

    @Test("Keeping a window narrows the pieces it crosses and drops the rest")
    func keepTimelineRange() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.split(atTimeline: 12)
        // Keep 5...14 of the timeline.
        let did14 = cuts.keep(fromTimeline: 5, toTimeline: 14)
        #expect(did14)
        #expect(cuts.timelineDuration == 9)
        #expect(cuts.pieces.map(\.start) == [5, 7, 12])
        #expect(cuts.pieces.map(\.end) == [7, 12, 14])
    }

    @Test("Keeping the whole timeline changes nothing")
    func keepWholeIsNoop() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        let before = cuts
        let did15 = cuts.keep(fromTimeline: 0, toTimeline: 18)
        #expect(did15)
        #expect(cuts == before)
    }

    @Test("Keeping a window that would leave nothing is refused")
    func keepNothingRefused() {
        var cuts = VideoCutList(duration: 18)
        let before = cuts
        let did16 = cuts.keep(fromTimeline: 5, toTimeline: 5)
        #expect(!did16)
        #expect(cuts == before)
    }

    @Test("Keeping a window inside one piece leaves exactly that piece")
    func keepInsideOnePiece() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        let did17 = cuts.keep(fromTimeline: 9, toTimeline: 13)
        #expect(did17)
        #expect(cuts.pieces.count == 1)
        #expect(cuts.pieces[0].start == 9)
        #expect(cuts.pieces[0].end == 13)
        #expect(cuts.timelineDuration == 4)
    }

    // MARK: - Talking to the rest of the video model

    @Test("An uncut list reads back as an ordinary trim")
    func singleTrimRoundTrip() {
        var cuts = VideoCutList(duration: 18)
        #expect(cuts.singleTrim?.inPoint == 0)
        #expect(cuts.singleTrim?.outPoint == 18)
        _ = cuts.keep(fromTimeline: 4, toTimeline: 10)
        #expect(cuts.singleTrim?.inPoint == 4)
        #expect(cuts.singleTrim?.outPoint == 10)
        _ = cuts.split(atTimeline: 2)
        #expect(cuts.singleTrim == nil)  // two pieces are not a trim
    }

    @Test("A trim converts into a one-piece cut list")
    func fromTrim() {
        let trim = VideoTrim(inPoint: 4, outPoint: 10, duration: 18)
        let cuts = VideoCutList(trim: trim)
        #expect(cuts.pieces.count == 1)
        #expect(cuts.pieces[0].start == 4)
        #expect(cuts.pieces[0].end == 10)
        #expect(cuts.sourceDuration == 18)
    }

    @Test("Source ranges come back in order for the composition builder")
    func sourceRanges() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.split(atTimeline: 12)
        _ = cuts.removePiece(at: 1)
        let ranges = cuts.sourceRanges
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0)
        #expect(ranges[0].length == 7)
        #expect(ranges[1].start == 12)
        #expect(ranges[1].length == 6)
    }

    // MARK: - Storage

    @Test("A cut list survives a Codable round trip")
    func codableRoundTrip() throws {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.removePiece(at: 0)
        let data = try JSONEncoder().encode(cuts)
        let back = try JSONDecoder().decode(VideoCutList.self, from: data)
        #expect(back == cuts)
    }

    @Test("Decoded pieces are clamped into the clip and never left empty")
    func normalizesOnConstruction() {
        let cuts = VideoCutList(pieces: [
            VideoPiece(start: -4, end: 3),
            VideoPiece(start: 5, end: 5),      // empty, dropped
            VideoPiece(start: 14, end: 40),    // clamped to the clip
        ], sourceDuration: 18)
        #expect(cuts.pieces.count == 2)
        #expect(cuts.pieces[0].start == 0)
        #expect(cuts.pieces[0].end == 3)
        #expect(cuts.pieces[1].start == 14)
        #expect(cuts.pieces[1].end == 18)
    }

    @Test("A cut list with no usable pieces falls back to the whole clip")
    func emptyFallsBackToWholeClip() {
        let cuts = VideoCutList(pieces: [], sourceDuration: 18)
        #expect(cuts.pieces.count == 1)
        #expect(cuts.isWholeClip)
    }

    @Test("Video edits carry a cut list alongside the trim")
    func editsCarryCuts() throws {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.removePiece(at: 0)
        let edits = VideoEdits(cuts: cuts)
        #expect(!edits.isEmpty)
        let data = try JSONEncoder().encode(edits)
        let back = try JSONDecoder().decode(VideoEdits.self, from: data)
        #expect(back.cuts == cuts)
    }

    @Test("A whole-clip cut list normalizes away, so it is not an edit")
    func wholeClipCutsNormalizeAway() {
        let edits = VideoEdits(cuts: VideoCutList(duration: 18))
        #expect(edits.normalized(videoSize: .zero).cuts == nil)
        #expect(edits.normalized(videoSize: .zero).isEmpty)
    }

    @Test("Old edits with no cuts key still decode")
    func legacyEditsDecode() throws {
        let json = #"{"trim":{"inPoint":1,"outPoint":5,"clipDuration":18}}"#
        let edits = try JSONDecoder().decode(VideoEdits.self, from: Data(json.utf8))
        #expect(edits.cuts == nil)
        #expect(edits.trim?.inPoint == 1)
    }

    @Test("Changing the cuts means the recording needs saving again")
    func needsSaveSeesCuts() {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 7)
        _ = cuts.removePiece(at: 0)
        let committed = VideoEdits()
        #expect(VideoSaveState.needsSave(edits: VideoEdits(cuts: cuts), committed: committed))
        #expect(!VideoSaveState.needsSave(edits: VideoEdits(cuts: cuts),
                                          committed: VideoEdits(cuts: cuts)))
    }
}

/// What a trim window does to each piece — the reading the trim handles draw
/// from, so what a person sees kept and what Done keeps are the same answer.
@Suite("Pieces under a trim window")
struct VideoPieceTrimTests {

    /// Three pieces of six seconds each, cut from an eighteen second recording.
    private func threePieces() -> VideoCutList {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 6)
        _ = cuts.split(atTimeline: 12)
        return cuts
    }

    @Test("An untouched window keeps every piece whole")
    func wholeWindowKeepsEverything() {
        let cuts = threePieces()
        let under = cuts.piecesUnderTrim(fromTimeline: 0, toTimeline: 18)
        #expect(under.count == 3)
        #expect(under.allSatisfy { $0.isWhollyKept })
        #expect(under.map(\.index) == [0, 1, 2])
        #expect(under[1].keptStart == 6)
        #expect(under[1].keptEnd == 12)
    }

    @Test("A window inside one piece drops the pieces either side of it")
    func windowInsideOnePiece() {
        let cuts = threePieces()
        let under = cuts.piecesUnderTrim(fromTimeline: 7, toTimeline: 9)
        #expect(under[0].isDropped)
        #expect(under[2].isDropped)
        #expect(!under[1].isDropped)
        #expect(!under[1].isWhollyKept)
        #expect(under[1].keptStart == 7)
        #expect(under[1].keptEnd == 9)
        #expect(under[1].keptDuration == 2)
    }

    @Test("A window across a join keeps the end of one piece and the start of the next")
    func windowCrossesAJoin() {
        let cuts = threePieces()
        let under = cuts.piecesUnderTrim(fromTimeline: 4, toTimeline: 8)
        #expect(under[0].keptStart == 4)
        #expect(under[0].keptEnd == 6)
        #expect(under[1].keptStart == 6)
        #expect(under[1].keptEnd == 8)
        #expect(under[2].isDropped)
    }

    @Test("A handle parked exactly on a join drops the piece it just left")
    func handleOnAJoinDropsWhatItLeft() {
        let cuts = threePieces()
        let under = cuts.piecesUnderTrim(fromTimeline: 6, toTimeline: 18)
        #expect(under[0].isDropped)
        #expect(under[1].isWhollyKept)
        #expect(under[2].isWhollyKept)
    }

    @Test("Handles dragged past each other read the same way round as applying them")
    func reversedWindowReadsTheSame() {
        let cuts = threePieces()
        #expect(cuts.piecesUnderTrim(fromTimeline: 9, toTimeline: 4)
                == cuts.piecesUnderTrim(fromTimeline: 4, toTimeline: 9))
    }

    @Test("An uncut recording is one piece, and the window narrows it")
    func uncutRecording() {
        let cuts = VideoCutList(duration: 18)
        let under = cuts.piecesUnderTrim(fromTimeline: 3, toTimeline: 15)
        #expect(under.count == 1)
        #expect(under[0].start == 0)
        #expect(under[0].end == 18)
        #expect(under[0].keptStart == 3)
        #expect(under[0].keptEnd == 15)
    }

    @Test("What the handles show as kept is exactly what applying the trim keeps")
    func drawingAgreesWithApplying() {
        let windows: [(TimeInterval, TimeInterval)] =
            [(0, 18), (4, 8), (7, 9), (6, 18), (0, 6), (2, 17), (6, 12), (5.5, 12.5)]
        for (from, to) in windows {
            let cuts = threePieces()
            let shownKept = cuts.piecesUnderTrim(fromTimeline: from, toTimeline: to)
                .filter { !$0.isDropped }
            var applied = cuts
            let didApply = applied.keep(fromTimeline: from, toTimeline: to)
            #expect(didApply, "window \(from)...\(to) should apply")
            #expect(applied.pieces.count == shownKept.count,
                    "window \(from)...\(to): \(shownKept.count) shown, \(applied.pieces.count) kept")
            for (shown, piece) in zip(shownKept, applied.pieces) {
                #expect(abs(shown.keptDuration - piece.duration) < 1e-9,
                        "window \(from)...\(to): shown \(shown.keptDuration), kept \(piece.duration)")
            }
        }
    }
}

// MARK: - A live trim window survives a piece being thrown away

/// Deleting a piece while the trim handles are open used to throw the window
/// away: the pieces got shorter and the window was reset to the whole clip, so
/// the handles a person had just placed jumped back to the ends. These pin the
/// window MOVING with the pieces instead — the same stretch of recording stays
/// inside it, measured against the shorter timeline.
struct VideoTrimAfterRemovingPieceTests {
    /// Three four-second pieces, twelve seconds of timeline.
    private func threePieces() -> VideoCutList {
        var cuts = VideoCutList(duration: 12)
        cuts.split(atTimeline: 4)
        cuts.split(atTimeline: 8)
        return cuts
    }

    @Test func aWindowAfterTheDroppedPieceSlidesBackByItsLength() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 9, outPoint: 11, duration: 12)
        let moved = cuts.trimAfterRemovingPiece(at: 0, from: window)
        #expect(abs(moved.inPoint - 5) < 1e-6)
        #expect(abs(moved.outPoint - 7) < 1e-6)
        #expect(abs(moved.clipDuration - 8) < 1e-6)
    }

    @Test func aWindowBeforeTheDroppedPieceStaysWhereItIs() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 1, outPoint: 3, duration: 12)
        let moved = cuts.trimAfterRemovingPiece(at: 2, from: window)
        #expect(abs(moved.inPoint - 1) < 1e-6)
        #expect(abs(moved.outPoint - 3) < 1e-6)
        #expect(abs(moved.clipDuration - 8) < 1e-6)
    }

    /// The window straddles the piece being dropped: it keeps its start, and
    /// its end comes back by the length that went out of the middle of it.
    @Test func aWindowAroundTheDroppedPieceShrinksByItsLength() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 2, outPoint: 10, duration: 12)
        let moved = cuts.trimAfterRemovingPiece(at: 1, from: window)
        #expect(abs(moved.inPoint - 2) < 1e-6)
        #expect(abs(moved.outPoint - 6) < 1e-6)
    }

    /// A handle standing inside the piece that is going lands on the join the
    /// delete closes, which is where that stretch of recording now is.
    @Test func aHandleInsideTheDroppedPieceLandsOnTheJoin() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 6, outPoint: 11, duration: 12)
        let moved = cuts.trimAfterRemovingPiece(at: 1, from: window)
        #expect(abs(moved.inPoint - 4) < 1e-6)
        #expect(abs(moved.outPoint - 7) < 1e-6)
    }

    /// Untouched handles stay untouched: a full-clip window is a full-clip
    /// window of whatever is left.
    @Test func anUnmovedWindowStaysTheWholeOfWhatIsLeft() {
        let cuts = threePieces()
        let moved = cuts.trimAfterRemovingPiece(at: 1, from: VideoTrim(duration: 12))
        #expect(!moved.isTrimmed)
        #expect(abs(moved.clipDuration - 8) < 1e-6)
    }

    /// The whole window was inside the piece that went. There is no stretch
    /// left for it to describe, so it opens back up to everything rather than
    /// becoming a sliver nobody asked for.
    @Test func aWindowWhollyInsideTheDroppedPieceOpensBackUp() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 5, outPoint: 7, duration: 12)
        let moved = cuts.trimAfterRemovingPiece(at: 1, from: window)
        #expect(!moved.isTrimmed)
        #expect(abs(moved.clipDuration - 8) < 1e-6)
    }

    /// An index that is not there, or the last piece (which cannot be dropped),
    /// leaves the window alone.
    @Test func anImpossibleRemovalLeavesTheWindowAlone() {
        let cuts = VideoCutList(duration: 12)
        let window = VideoTrim(inPoint: 2, outPoint: 10, duration: 12)
        #expect(cuts.trimAfterRemovingPiece(at: 0, from: window) == window)
        #expect(threePieces().trimAfterRemovingPiece(at: 7, from: window) == window)
    }

    /// The promise the whole thing rests on: what the moved window keeps of the
    /// shortened timeline is the same recording as what the old window kept of
    /// the old one, minus whatever of it was in the piece that went.
    @Test func theMovedWindowKeepsTheSameRecording() {
        let cuts = threePieces()
        let window = VideoTrim(inPoint: 2, outPoint: 10, duration: 12)

        var before = cuts
        before.keep(fromTimeline: window.inPoint, toTimeline: window.outPoint)
        var withoutMiddle = before
        // The middle piece, as the window left it, is the second of three.
        withoutMiddle.removePiece(at: 1)

        // Read against the list that STILL has the piece, which is what the
        // caller has in hand at the moment the person presses Delete.
        let moved = cuts.trimAfterRemovingPiece(at: 1, from: window)
        var after = cuts
        after.removePiece(at: 1)
        var kept = after
        kept.keep(fromTimeline: moved.inPoint, toTimeline: moved.outPoint)

        #expect(kept.pieces == withoutMiddle.pieces)
    }
}
