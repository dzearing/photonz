import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// J played a full-screen Retina recording backwards one exact frame at a
/// time, each a seek from the key frame before it, and the picture stuck:
/// End then J held a frame up to 22 behind at 14 of 20 looks, J J up to 38 at
/// 15 of 20 (`playing-backwards-with-j-keeps-up-on-a-full-scre`, measured
/// 2026-10-08). A file is read forwards only, so playing backwards reads the
/// stretch just behind the playhead in blocks, each block in one pass.
@Suite("Reading behind a playhead playing backwards, a block at a time")
struct MoviePlayBackwardTests {

    /// A 3.6s recording: grid frames 0 to 109.
    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 3600)
    private var last: Int { movie.frameIndex(atSourceMS: movie.durationMS) }
    private var lead: Int { MoviePlayBackward.reach(speed: 1) }
    private var block: Int { MoviePlayBackward.blockLength(speed: 1) }

    @Test("From cold, the block ends on the first frame behind the playhead not in hand")
    func coldStart() {
        let next = MoviePlayBackward.next(playhead: last, speed: 1, movie: movie,
                                          inHand: { $0 == last }, running: [])
        #expect(next == (last - block)...(last - 1))
    }

    @Test("Nothing is read while every frame within reach behind the playhead is in hand")
    func nothingToRead() {
        let next = MoviePlayBackward.next(playhead: 80, speed: 1, movie: movie,
                                          inHand: { $0 >= 80 - lead }, running: [])
        #expect(next == nil)
    }

    @Test("A block being read counts as in hand, and the next one starts below it")
    func pipelines() {
        let running = [(80 - block)...79]
        let next = MoviePlayBackward.next(playhead: 80, speed: 1, movie: movie,
                                          inHand: { $0 >= 80 }, running: running)
        #expect(next == nil || next?.upperBound ?? 0 < 80 - block)
        // Once the playhead is within reach of the bottom of it, the next.
        let low = 80 - block
        let later = MoviePlayBackward.next(playhead: low + lead - 1, speed: 1, movie: movie,
                                           inHand: { $0 >= low && $0 < 80 }, running: [])
        #expect(later == (low - block)...(low - 1))
    }

    // From rest the first block decodes from the key frame before it, and a
    // second block opened beside it decodes the same stretch and halves the
    // speed of both (measured 2026-10-08: the frame behind the playhead took
    // 312ms with two, the block alone about 200ms).
    @Test("While the block right behind the playhead is being read, no second one competes")
    func urgentAlone() {
        let urgent = [(last - block)...(last - 1)]
        #expect(MoviePlayBackward.next(playhead: last, speed: 1, movie: movie,
                                       inHand: { $0 == last }, running: urgent) == nil)
        // Once the playhead is well above it, the next one may start beside it.
        let next = MoviePlayBackward.next(playhead: 80, speed: 1, movie: movie,
                                          inHand: { $0 >= 77 }, running: [72...76])
        #expect(next == (72 - block)...71)
    }

    @Test("Playing backwards is ready once the frame behind the playhead is in hand")
    func ready() {
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let at = 90 * MovieRef.frameStepMS
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 90)
        #expect(!document.readyToPlayBackward(atTimeMS: at, inHand: hand))
        hand.insert(movie: movie.id, frameIndex: 89)
        #expect(document.readyToPlayBackward(atTimeMS: at, inHand: hand))
        // At the first frame there is nothing behind to wait for.
        #expect(document.readyToPlayBackward(atTimeMS: 0, inHand: MovieFramesInHand()))
    }

    // Played backwards across a cut, the playhead jumps to the frame before
    // the cut, and a block opened only on arrival left the picture 22 frames
    // behind there, while the stretch playing read on past the cut into
    // frames never shown (2026-10-08).
    @Test("Played backwards toward a cut, the stretch stops at the cut and its far side is a place too")
    func places() throws {
        let long = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 8000)
        var document = PhotonzDocument.recording(long, name: "Take 1")
        let id = try #require(document.layers.first).id
        // 0 to 3s of the file, then 5s to 8s: the cut is at 3s on the clock.
        document.updateLayer(id: id) {
            $0.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 3000),
                                                 ClipPiece(sourceInMS: 5000, lengthMS: 3000)],
                                        sourceLengthMS: 8000))
        }
        let step = MovieRef.frameStepMS
        let cutFrame = long.frameIndex(atSourceMS: 5000)
        // Five frames after the cut on the clock, going backwards.
        let places = document.moviePlayBackPlaces(atTimeMS: 3000 + 5 * step, speed: 1)
        #expect(places.count == 2)
        #expect(places.first?.head == cutFrame + 5)
        #expect(places.first?.floor == cutFrame)
        let far = try #require(places.last)
        #expect(far.head == long.frameIndex(atSourceMS: 3000 - step))
        #expect(far.floor < far.head)
        // Far from any cut, one place reading down a whole reach and block.
        let plain = document.moviePlayBackPlaces(atTimeMS: 6000, speed: 1)
        #expect(plain.count == 1)
        #expect((plain.first.map { $0.head - $0.floor } ?? 0) >= lead + block)
    }

    @Test("A block never reads below the stretch's floor")
    func floor() {
        let next = MoviePlayBackward.next(playhead: 60, floor: 56, speed: 1, movie: movie,
                                          inHand: { $0 == 60 }, running: [])
        #expect(next == 56...59)
    }

    @Test("Blocks read for another place in the recording neither count nor wait against this one")
    func unrelatedBlocks() {
        // A block for the stretch playing, far above the frame across a cut.
        let next = MoviePlayBackward.next(playhead: 27, speed: 1, movie: movie,
                                          inHand: { _ in false }, running: [50...59, 60...69])
        #expect(next == (28 - block)...27)
    }

    @Test("No more than two blocks read at once")
    func twoAtOnce() {
        let running = [70...79, 60...69]
        let next = MoviePlayBackward.next(playhead: 80, speed: 1, movie: movie,
                                          inHand: { _ in false }, running: running)
        #expect(next == nil)
    }

    @Test("A block never runs below the first frame, nor into a block already being read")
    func clamps() {
        #expect(MoviePlayBackward.next(playhead: 5, speed: 1, movie: movie,
                                       inHand: { $0 == 5 }, running: []) == 0...4)
        let next = MoviePlayBackward.next(playhead: 40, speed: 1, movie: movie,
                                          inHand: { $0 >= 35 }, running: [30...31])
        #expect(next == 32...34)
    }

    @Test("Faster backwards reads further behind, up to twice as far")
    func speed() {
        #expect(MoviePlayBackward.reach(speed: 2) == 2 * lead)
        #expect(MoviePlayBackward.blockLength(speed: 2) == 2 * block)
        #expect(MoviePlayBackward.reach(speed: 8) == MoviePlayBackward.reach(speed: 2))
        #expect(MoviePlayBackward.reach(speed: 0.5) == lead)
    }

    @Test("A block the playhead has gone past, or jumped far away from, no longer serves")
    func serves() {
        #expect(MoviePlayBackward.serves(70...79, playhead: 85, speed: 1))
        #expect(!MoviePlayBackward.serves(70...79, playhead: 69, speed: 1))
        #expect(!MoviePlayBackward.serves(10...19, playhead: 100, speed: 1))
    }

    @Test("A frame a running block will reach is not read on its own")
    func covers() {
        #expect(MoviePlayBackward.covers(frame: 75, running: [70...79]))
        #expect(!MoviePlayBackward.covers(frame: 80, running: [70...79]))
    }

    @Test("The window keeps room for the frame under the playhead, the reach and a block below it")
    func budget() {
        #expect(MoviePlayBackward.frameBudget(base: 16, speed: 1)
            == 1 + lead + block + MoviePlayPass.fallenBehindFrames)
        #expect(MoviePlayBackward.frameBudget(base: 200, speed: 1) == 200)
        #expect(MoviePlayBackward.frameBudget(base: 16, speed: 1, places: 2)
            == 2 * (1 + lead + block) + MoviePlayPass.fallenBehindFrames)
    }

    // Played backwards the frames gone by are the ones ABOVE the playhead,
    // and the block just read below it is what is shown next.
    @Test("Playing backwards, a frame already shown goes before one read for what comes next")
    func backwardEviction() {
        let movie = UUID()
        let resident = [(movie: movie, frame: 60), (movie: movie, frame: 88)]
        // 88 is 8 gone by, 60 is 20 to come: the one gone by goes.
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: [80]], backward: true) == 1)
        // Even one gone by a few frames goes before the bottom of the block
        // below the reach.
        let near = [(movie: movie, frame: 59), (movie: movie, frame: 83)]
        #expect(MovieFrameQueue<Int>.farthest(near, from: [movie: [80]], backward: true) == 1)
        // Without a direction, plain distance.
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: [80]]) == 0)
    }
}
