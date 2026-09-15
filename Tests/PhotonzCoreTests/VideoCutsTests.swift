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
