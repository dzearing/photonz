import Foundation
import PhotonzCore
import Testing

/// **A retimed clip shows its length at 100%**, the striped Source bar the
/// speed mock draws above the retimed clip (`video-speed.html`, `.srcbar`).
///
/// The ghost is a view of the clip, never part of the document: it starts
/// where the clip starts and is as long as the clip would be if every piece
/// that plays played as recorded. Written before the code, which is the rule
/// for `PhotonzCore`.
@Suite("A retimed clip's Source ghost")
struct ClipSourceGhostTests {

    @Test("A clip at 100% has no ghost")
    func asRecordedHasNone() {
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 4000)])
        #expect(ClipSourceGhost(pieces: pieces, startMS: 1000) == nil)
    }

    @Test("Slowed to half, the ghost is the length it was, starting where the clip starts")
    func slowed() throws {
        // 50% makes four seconds of recording take eight on the timeline.
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 8000, speedPercent: 50)])
        let ghost = try #require(ClipSourceGhost(pieces: pieces, startMS: 1500))
        #expect(ghost.startMS == 1500)
        #expect(ghost.lengthMS == 4000)
        #expect(ghost.endMS == 5500)
        #expect(ghost.retimedLengthMS == 8000)
    }

    @Test("Sped up, the ghost runs past the clip's end")
    func spedUp() throws {
        // Twice as fast: eight seconds of recording in four.
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 2000, lengthMS: 4000, speedPercent: 200)])
        let ghost = try #require(ClipSourceGhost(pieces: pieces, startMS: 0))
        #expect(ghost.lengthMS == 8000)
        #expect(ghost.retimedLengthMS == 4000)
    }

    @Test("A cut clip adds each piece at 100%, and a held frame keeps its length")
    func cutAndHeld() throws {
        let pieces = ClipPieces(pieces: [
            ClipPiece(sourceInMS: 0, lengthMS: 2000),
            ClipPiece(sourceInMS: 2000, lengthMS: 4000, speedPercent: 50),
            .held(atSourceMS: 4000, forMS: 1000),
        ])
        let ghost = try #require(ClipSourceGhost(pieces: pieces, startMS: 0))
        #expect(ghost.lengthMS == 2000 + 2000 + 1000)
        #expect(ghost.retimedLengthMS == 7000)
    }

    @Test("A held frame alone is not a retime, so there is no ghost")
    func holdAloneHasNone() {
        let pieces = ClipPieces(pieces: [
            ClipPiece(sourceInMS: 0, lengthMS: 2000),
            .held(atSourceMS: 2000, forMS: 2000),
        ])
        #expect(ClipSourceGhost(pieces: pieces, startMS: 0) == nil)
    }
}
