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
        let at = MovieRef.gridMS(ofFrame: 90)
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 90)
        #expect(!document.readyToPlayBackward(atTimeMS: at, inHand: hand))
        hand.insert(movie: movie.id, frameIndex: 89)
        #expect(document.readyToPlayBackward(atTimeMS: at, inHand: hand))
        // At the first frame there is nothing behind to wait for.
        #expect(document.readyToPlayBackward(atTimeMS: 0, inHand: MovieFramesInHand()))
    }

    // On the six minute reference edit, 4x forwards from rest held a frame 15
    // behind at its first look, half a second in, while the pass decoded from
    // the key frame before the playhead; every look after kept up
    // (2026-11-13). Above 2x the sound is silent, so the clock waits for the
    // first frame the way it does backwards.
    @Test("Playing fast forwards is ready once the first frame it keeps at or after the playhead is in hand")
    func readyForwards() {
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let at = MovieRef.gridMS(ofFrame: 91)
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 90)
        #expect(!document.readyToPlayForward(atTimeMS: at, inHand: hand, speed: 4))
        hand.insert(movie: movie.id, frameIndex: 91)
        #expect(document.readyToPlayForward(atTimeMS: at, inHand: hand, speed: 4))
        // At 8x only every third frame is kept: 93 is the one it waits for.
        #expect(!document.readyToPlayForward(atTimeMS: at, inHand: hand, speed: 8))
        hand.insert(movie: movie.id, frameIndex: 93)
        #expect(document.readyToPlayForward(atTimeMS: at, inHand: hand, speed: 8))
        // A document with no recording in it has nothing to wait for.
        #expect(PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
            .readyToPlayForward(atTimeMS: at, inHand: MovieFramesInHand(), speed: 4))
    }

    // Space right after a scrub that landed a second past a key frame of the
    // user's HEVC screen recording: the frame under the playhead was in hand
    // (the scrub had read it), the frames after it were not, and the pass
    // decoding up to them from the key frame took about half a second while
    // the clock ran on. Both sides of a dissolve held a frame up to 10 behind
    // at 14 of 24 looks (`a-cross-fade-plays-smoothly-in-the-editor-the-wa`,
    // 2026-11-20). With sound too, the clock waits for the frames just ahead.
    @Test("Playing with sound is ready once the frame under the playhead and the next few are in hand")
    func readyToStartWithSound() {
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let at = MovieRef.gridMS(ofFrame: 60)
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 60)
        // The frame under the playhead alone is what fast play waits for...
        #expect(document.readyToPlayForward(atTimeMS: at, inHand: hand, speed: 4))
        // ...but at a speed with sound the next frames have to be there too.
        for speed in [0.5, 1, 2] {
            #expect(!document.readyToStartPlaying(atTimeMS: at, inHand: hand, speed: speed))
        }
        let ahead = MoviePlayPass.startsWithFramesAhead
        #expect(ahead >= 2)
        for frame in 61..<(60 + ahead) { hand.insert(movie: movie.id, frameIndex: frame) }
        #expect(!document.readyToStartPlaying(atTimeMS: at, inHand: hand, speed: 1))
        hand.insert(movie: movie.id, frameIndex: 60 + ahead)
        for speed in [0.5, 1, 2] {
            #expect(document.readyToStartPlaying(atTimeMS: at, inHand: hand, speed: speed))
        }
        // Above double speed it is the fast rule, unchanged.
        var under = MovieFramesInHand()
        under.insert(movie: movie.id, frameIndex: 60)
        #expect(document.readyToStartPlaying(atTimeMS: at, inHand: under, speed: 4))
        // Near the last frame only the frames there are waited for.
        let end = MovieRef.gridMS(ofFrame: last)
        var tail = MovieFramesInHand()
        tail.insert(movie: movie.id, frameIndex: last)
        #expect(document.readyToStartPlaying(atTimeMS: end, inHand: tail, speed: 1))
        // A document with no recording in it has nothing to wait for.
        #expect(PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
            .readyToStartPlaying(atTimeMS: at, inHand: MovieFramesInHand(), speed: 1))
        // The wait is bounded: longer than the half second the first decode
        // took, never so long that pressing Space feels ignored.
        #expect(MoviePlayPass.soundStartWaitMS > 614 && MoviePlayPass.soundStartWaitMS <= 1000)
    }

    // Space on the 50 track edit at 0:58 waited out its whole 800 ms for
    // frames of clips under a full-frame one, which nothing reads while it
    // plays (2026-11-25).
    @Test("A start waits for the clips that are seen, never for one hidden under another")
    func startsWithoutTheHidden() {
        let size = CGSize(width: 1600, height: 1000)
        func clip(_ movie: MovieRef) -> Layer {
            var layer = Layer(name: "clip", content: .image(movie.frameRef(atSourceMS: 0)),
                              frame: CGRect(origin: .zero, size: size))
            layer.movie = movie
            layer.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: movie.durationMS)
            return layer
        }
        let under = MovieRef(pixelSize: size, durationMS: 8000), over = MovieRef(pixelSize: size, durationMS: 8000)
        var document = PhotonzDocument(canvasSize: size, layers: [clip(under), clip(over)])
        document.durationMS = 8000
        let at = MovieRef.gridMS(ofFrame: 60)
        var hand = MovieFramesInHand()
        for frame in 60...(60 + MoviePlayPass.startsWithFramesAhead) { hand.insert(movie: over.id, frameIndex: frame) }
        #expect(document.movieFrames(atTimeMS: at).count == 2)
        for speed in [0.5, 1, 2, 4] {
            #expect(document.readyToStartPlaying(atTimeMS: at, inHand: hand, speed: speed))
        }
    }

    // Ten recordings decode up from ten key frames on one decoder: half a
    // second and more before the last of them has the frames ahead
    // (2026-11-25). The clock goes once some of them are there.
    @Test("With many recordings on screen the clock does not hold for the last of them")
    func movesOnWithoutThemAll() {
        let moveOn = Double(MoviePlayPass.movesOnAfterMS)
        #expect(moveOn < 80)
        func start(_ clips: Int, landed: Int, ready: Int, waitsOn: Int = 0) -> MoviePlayPass.StartReady {
            MoviePlayPass.StartReady(clips: clips, landed: landed, ready: ready, waitsOn: waitsOn)
        }
        let six = start(6, landed: 6, ready: 2)
        #expect(!MoviePlayPass.starts(six, waitedMS: moveOn - 1))
        #expect(MoviePlayPass.starts(six, waitedMS: moveOn))
        // Everything there: at once.
        #expect(MoviePlayPass.starts(start(6, landed: 6, ready: 6), waitedMS: 0))
        #expect(MoviePlayPass.starts(start(0, landed: 0, ready: 0), waitedMS: 0))
        // Few on screen: the picture IS those clips, and a clock run on
        // without them is a frozen picture over moving sound (2026-11-20).
        #expect(!MoviePlayPass.starts(start(2, landed: 2, ready: 1), waitedMS: moveOn))
        #expect(!MoviePlayPass.starts(start(3, landed: 2, ready: 2), waitedMS: moveOn))
        #expect(!MoviePlayPass.starts(start(6, landed: 6, ready: 0), waitedMS: moveOn))
        // A small clip with no frame of its own is left out meanwhile; a big
        // one is not, it would be a hole in the picture.
        #expect(MoviePlayPass.starts(start(6, landed: 4, ready: 2), waitedMS: moveOn))
        #expect(!MoviePlayPass.starts(start(6, landed: 5, ready: 5, waitsOn: 1), waitedMS: moveOn))
        // ...and at least half of them are there: more would be chasing the
        // clock than the decoder has room for.
        #expect(MoviePlayPass.starts(start(10, landed: 5, ready: 5), waitedMS: moveOn))
        #expect(!MoviePlayPass.starts(start(10, landed: 4, ready: 4), waitedMS: moveOn))
        #expect(!start(6, landed: 5, ready: 5, waitsOn: 1).isAPicture)
        // Never longer than the wait.
        #expect(MoviePlayPass.starts(start(6, landed: 0, ready: 0, waitsOn: 1),
                                     waitedMS: Double(MoviePlayPass.soundStartWaitMS)))
    }

    @Test("A clip a start went without is never stood in for from another time")
    func nothingFromAnotherTime() {
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 10)
        hand.insert(movie: movie.id, frameIndex: 200)
        #expect(hand.frameIndexToShow(60, of: movie.id) == 10)
        hand.nearOnly = MoviePlayPass.startStandInFrames
        #expect(hand.frameIndexToShow(60, of: movie.id) == nil)
        hand.insert(movie: movie.id, frameIndex: 61)
        #expect(hand.frameIndexToShow(60, of: movie.id) == nil)
        hand.insert(movie: movie.id, frameIndex: 55)
        #expect(hand.frameIndexToShow(60, of: movie.id) == 55)
        #expect(hand.frameIndexToShow(61, of: movie.id) == 61)
    }

    @Test("What a start has ready is counted clip by clip")
    func startReady() {
        let size = CGSize(width: 1600, height: 1000)
        let movies = (0..<5).map { _ in MovieRef(pixelSize: size, durationMS: 8000) }
        let layers = movies.enumerated().map { index, movie -> Layer in
            var layer = Layer(name: "clip", content: .image(movie.frameRef(atSourceMS: 0)),
                              frame: CGRect(x: CGFloat(index) * 100, y: 0, width: 90, height: 60))
            layer.movie = movie
            layer.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: movie.durationMS)
            return layer
        }
        var document = PhotonzDocument(canvasSize: size, layers: layers)
        document.durationMS = 8000
        let at = MovieRef.gridMS(ofFrame: 60)
        var hand = MovieFramesInHand()
        for movie in movies { hand.insert(movie: movie.id, frameIndex: 60) }
        for frame in 61...63 { hand.insert(movie: movies[0].id, frameIndex: frame) }
        hand.insert(movie: movies[1].id, frameIndex: 61)
        #expect(document.startReady(atTimeMS: at, inHand: hand, speed: 1)
            == MoviePlayPass.StartReady(clips: 5, landed: 5, ready: 1, waitsOn: 0))
        hand.remove(movie: movies[4].id, frameIndex: 60)
        #expect(document.startReady(atTimeMS: at, inHand: hand, speed: 1)
            == MoviePlayPass.StartReady(clips: 5, landed: 4, ready: 1, waitsOn: 0))
        document.layers[4].frame.size = size
        #expect(document.startReady(atTimeMS: at, inHand: hand, speed: 1).waitsOn == 1)
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
        let places = document.moviePlayBackPlaces(atTimeMS: MovieRef.gridMS(steppedFrom: 3000, byFrames: 5), speed: 1)
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

    @Test("Faster backwards reads further behind, holding up to twice as many frames")
    func speed() {
        #expect(MoviePlayBackward.reach(speed: 2) == 2 * lead)
        #expect(MoviePlayBackward.blockLength(speed: 2) == 2 * block)
        #expect(MoviePlayBackward.reach(speed: 4) == MoviePlayBackward.reach(speed: 2))
        #expect(MoviePlayBackward.reach(speed: 0.5) == lead)
    }

    // J J J J on the five minute Retina talk held a frame up to 13 behind at
    // 12 of 24 looks, where J J J kept up at every one (measured 2026-10-08).
    // At 8x the clock shows one frame in eight, so reading and keeping every
    // frame is twice the work 4x does for nothing anybody sees.
    @Test("At 8x backwards every third frame is kept, and 4x and slower keep every frame")
    func stride() {
        #expect(MoviePlayBackward.stride(speed: 1) == 1)
        #expect(MoviePlayBackward.stride(speed: 2) == 1)
        #expect(MoviePlayBackward.stride(speed: 4) == 1)
        #expect(MoviePlayBackward.stride(speed: 8) == 3)
        #expect(MoviePlayBackward.keeps(frame: 39, speed: 8))
        #expect(!MoviePlayBackward.keeps(frame: 40, speed: 8))
        #expect(!MoviePlayBackward.keeps(frame: 41, speed: 8))
        #expect(MoviePlayBackward.keeps(frame: 41, speed: 4))
    }

    @Test("At 8x backwards the reads reach further back in time than at 4x, holding the same number of frames")
    func eightTimes() {
        let four = MoviePlayBackward.reach(speed: 4)
        #expect(MoviePlayBackward.reach(speed: 8) == 3 * four)
        #expect(MoviePlayBackward.blockLength(speed: 8) == 3 * MoviePlayBackward.blockLength(speed: 4))
        #expect(MoviePlayBackward.frameBudget(base: 16, speed: 8)
            == MoviePlayBackward.frameBudget(base: 16, speed: 4))
    }

    @Test("At 8x backwards a frame that is not kept is never waited for nor read")
    func eightTimesSkips() {
        let reach = MoviePlayBackward.reach(speed: 8)
        // Every kept frame within reach is in hand: nothing to read, though
        // the frames between them are not.
        #expect(MoviePlayBackward.next(playhead: 100, speed: 8, movie: movie,
                                       inHand: { $0 >= 100 - reach && $0 % 3 == 0 }, running: []) == nil)
        // From cold on a frame not kept, the block ends on the first kept frame below.
        let next = MoviePlayBackward.next(playhead: 101, speed: 8, movie: movie,
                                          inHand: { $0 == 101 }, running: [])
        #expect(next?.upperBound == 99)
        #expect(next?.count == MoviePlayBackward.blockLength(speed: 8))
    }

    @Test("At 8x backwards it is ready once the kept frame behind the playhead is in hand")
    func readyAtEightTimes() {
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        // The frame behind 92 is 91, and the kept frame at or below it is 90.
        let at = MovieRef.gridMS(ofFrame: 92)
        var hand = MovieFramesInHand()
        hand.insert(movie: movie.id, frameIndex: 92)
        #expect(!document.readyToPlayBackward(atTimeMS: at, inHand: hand, speed: 8))
        hand.insert(movie: movie.id, frameIndex: 90)
        #expect(document.readyToPlayBackward(atTimeMS: at, inHand: hand, speed: 8))
        // Slower, it is the very frame behind that counts.
        #expect(!document.readyToPlayBackward(atTimeMS: at, inHand: hand, speed: 4))
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
