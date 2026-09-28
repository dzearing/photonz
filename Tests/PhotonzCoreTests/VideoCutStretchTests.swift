import Foundation
import Testing
@testable import PhotonzCore

/// A stretch of what plays, as the pieces of the source file it is read from:
/// what the Export sheet writes to weigh a cut recording
/// (`VideoExportSample`).
@Suite("A stretch of the timeline, read back from the source")
struct VideoCutStretchTests {

    private let cut = VideoCutList(pieces: [VideoPiece(start: 2, end: 5),
                                            VideoPiece(start: 10, end: 14)],
                                   sourceDuration: 20)

    @Test func aStretchInsideOnePieceIsThatPartOfIt() {
        let stretch = cut.sourcePieces(fromTimeline: 1, to: 2.5)
        #expect(stretch == [VideoPiece(start: 3, end: 4.5)])
    }

    /// Across a cut it is the end of one piece and the start of the next, in
    /// play order, which is what the export itself writes there.
    @Test func aStretchAcrossACutIsBothSidesOfIt() {
        let stretch = cut.sourcePieces(fromTimeline: 2, to: 5)
        #expect(stretch == [VideoPiece(start: 4, end: 5), VideoPiece(start: 10, end: 12)])
    }

    @Test func aStretchPastTheEndStopsAtTheEnd() {
        let stretch = cut.sourcePieces(fromTimeline: 6, to: 30)
        #expect(stretch == [VideoPiece(start: 13, end: 14)])
    }

    @Test func anEmptyStretchIsNoPieces() {
        #expect(cut.sourcePieces(fromTimeline: 3, to: 3).isEmpty)
        #expect(cut.sourcePieces(fromTimeline: 9, to: 12).isEmpty)
    }
}
