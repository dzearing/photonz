import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Playing a recording never blinks (`playing-a-recording-never-blinks`).
///
/// A frame the app has not finished reading yet used to be drawn as nothing at
/// all, because the clip swapped to the new frame's reference whether or not
/// anybody had decoded it. The fix is said here, in the model, where it can be
/// tested without a decoder: the document is drawn with the frames IN HAND, and
/// a frame not in hand is stood in for by the newest one that is.
@Suite("A late frame holds the last good picture")
struct FramesInHandTests {

    static func movie(durationMS: Int = 8000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                 pixelSize: CGSize(width: 3456, height: 2234),
                 durationMS: durationMS)
    }

    static func ms(_ frame: Int) -> Int { frame * MovieRef.frameStepMS }

    static func clipRef(_ document: PhotonzDocument) -> ImageRef? {
        guard case .image(let ref) = document.layers.first?.content else { return nil }
        return ref
    }

    // MARK: - Choosing the frame to show

    @Test("The frame asked for is shown when it is in hand")
    func theWantedFrameWins() {
        let movie = Self.movie()
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 3)
        inHand.insert(movie: movie.id, frameIndex: 5)
        #expect(inHand.frameIndexToShow(5, of: movie.id) == 5)
    }

    @Test("A frame not yet read is stood in for by the newest one at or before it")
    func newestAtOrBefore() {
        let movie = Self.movie()
        var inHand = MovieFramesInHand()
        for index in [0, 3, 7] { inHand.insert(movie: movie.id, frameIndex: index) }
        #expect(inHand.frameIndexToShow(5, of: movie.id) == 3)
        #expect(inHand.frameIndexToShow(6, of: movie.id) == 3)
        #expect(inHand.frameIndexToShow(9, of: movie.id) == 7)
    }

    @Test("With nothing earlier in hand, the nearest later frame beats a blank")
    func nearestLaterWhenNothingEarlier() {
        let movie = Self.movie()
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 8)
        inHand.insert(movie: movie.id, frameIndex: 12)
        #expect(inHand.frameIndexToShow(2, of: movie.id) == 8)
    }

    @Test("Nothing in hand for a recording means nothing to stand in")
    func nothingInHand() {
        let movie = Self.movie()
        var inHand = MovieFramesInHand()
        inHand.insert(movie: UUID(), frameIndex: 4)
        #expect(inHand.frameIndexToShow(4, of: movie.id) == nil)
    }

    @Test("A frame let go is no longer in hand")
    func removing() {
        let movie = Self.movie()
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 3)
        inHand.insert(movie: movie.id, frameIndex: 4)
        inHand.remove(movie: movie.id, frameIndex: 4)
        #expect(inHand.contains(movie: movie.id, frameIndex: 3))
        #expect(!inHand.contains(movie: movie.id, frameIndex: 4))
        #expect(inHand.frameIndexToShow(4, of: movie.id) == 3)
    }

    // MARK: - The drawn document

    @Test("The drawn document uses the newest decoded frame at or before the moment")
    func drawnHoldsTheLastFrame() throws {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        var inHand = MovieFramesInHand()
        inHand.insert(movie: movie.id, frameIndex: 10)
        inHand.insert(movie: movie.id, frameIndex: 11)
        // Frame 14 is on its way: 11 is what the canvas should keep showing.
        let shown = document.drawn(atTimeMS: Self.ms(14) + 5, framesInHand: inHand)
        #expect(Self.clipRef(shown) == movie.frameRef(atSourceMS: Self.ms(11)))
        // ...and the moment it lands, it is what is drawn.
        inHand.insert(movie: movie.id, frameIndex: 14)
        let landed = document.drawn(atTimeMS: Self.ms(14) + 5, framesInHand: inHand)
        #expect(Self.clipRef(landed) == movie.frameRef(atSourceMS: Self.ms(14)))
        // The document the landing draws differs from the one before it, so
        // the canvas has something to redraw.
        #expect(shown != landed)
    }

    @Test("Without frames in hand the document asks for exactly the frame at the moment")
    func withoutInHandNothingChanges() {
        let movie = Self.movie()
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let plain = document.drawn(atTimeMS: Self.ms(14))
        #expect(Self.clipRef(plain) == movie.frameRef(atSourceMS: Self.ms(14)))
        // An export draws this way: it waits for the exact frame, never a
        // stand-in, so an empty hand must not change the answer either.
        let empty = document.drawn(atTimeMS: Self.ms(14), framesInHand: MovieFramesInHand())
        #expect(Self.clipRef(empty) == movie.frameRef(atSourceMS: Self.ms(14)))
    }

    @Test("A dissolve's incoming shot holds its last frame too")
    func transitionPartnerHolds() throws {
        let movie = Self.movie()
        var document = PhotonzDocument.recording(movie, name: "Take 1")
        let id = try #require(document.layers.first).id
        document.updateLayer(id: id) {
            $0.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 3000),
                                                 ClipPiece(sourceInMS: 5000, lengthMS: 3000)],
                                        sourceLengthMS: 8000))
        }
        let put = document.setClipTransition(id, atCut: 1,
                                             to: ClipTransition(kind: .dissolve, lengthMS: 1000))
        #expect(put)
        let moment = 3000
        let requests = document.movieFrames(atTimeMS: moment)
        #expect(requests.count == 2)
        var inHand = MovieFramesInHand()
        for request in requests {
            let index = movie.frameIndex(atSourceMS: request.sourceMS)
            // Everything a couple of frames short of what is wanted.
            inHand.insert(movie: movie.id, frameIndex: index - 2)
        }
        let shown = document.drawn(atTimeMS: moment, framesInHand: inHand)
        let refs = shown.layers.compactMap { layer -> ImageRef? in
            guard case .image(let ref) = layer.content else { return nil }
            return ref
        }
        let wantedHeld = requests.map {
            movie.frameRef(atSourceMS: (movie.frameIndex(atSourceMS: $0.sourceMS) - 2) * MovieRef.frameStepMS)
        }
        #expect(Set(refs) == Set(wantedHeld))
    }

    // MARK: - How big a frame is worth reading

    @Test("A frame is read at the size it is shown, never bigger than the recording")
    func decodeSizeFollowsTheScreen() {
        let movie = Self.movie()
        // Shown at half size: read at half size.
        #expect(movie.decodePixelSize(shownScale: 0.5) == CGSize(width: 1728, height: 1117))
        // Shown bigger than it is: the recording's own size, never more.
        #expect(movie.decodePixelSize(shownScale: 2) == movie.pixelSize)
        // In steps of an eighth, so a zoom that wobbles does not throw every
        // frame away and read it again.
        #expect(movie.decodePixelSize(shownScale: 0.51) == movie.decodePixelSize(shownScale: 0.62))
        // ...and never so small a stray tiny zoom reads a smudge.
        #expect(movie.decodePixelSize(shownScale: 0.001).width == 432)
    }
}
