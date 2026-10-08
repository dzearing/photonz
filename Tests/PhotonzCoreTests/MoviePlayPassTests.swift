import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Playing a full-screen Retina recording showed a frame up to half a second
/// old (`a-full-screen-retina-recording-keeps-up-while-it`). Reproduced by
/// `playing-a-recording-never-blinks-walk`: 17 of 24 looks held a frame 16
/// behind. Reading exact frames one at a time managed about 15 a second on the
/// fixture, four side by side; one pass reads the same three seconds in half a
/// second. So playing reads in one pass that keeps a little ahead of the
/// playhead, and is started again when the playhead goes somewhere it is not.
@Suite("Reading ahead of a playing playhead in one pass")
struct MoviePlayPassTests {

    /// A 3.6s recording: grid frames 0 to 109.
    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 3600)
    private var last: Int { movie.frameIndex(atSourceMS: movie.durationMS) }

    @Test("A pass runs from the playhead to the end of the recording")
    func window() {
        #expect(MoviePlayPass.window(from: 30, movie: movie) == 30...last)
        #expect(MoviePlayPass.window(from: -4, movie: movie) == 0...last)
        #expect(MoviePlayPass.window(from: last + 9, movie: movie) == last...last)
    }

    @Test("A pass waits once it is far enough ahead of the playhead")
    func pacing() {
        #expect(!MoviePlayPass.shouldWait(next: 10 + MoviePlayPass.aheadFrames, playhead: 10))
        #expect(MoviePlayPass.shouldWait(next: 11 + MoviePlayPass.aheadFrames, playhead: 10))
        #expect(!MoviePlayPass.shouldWait(next: 3, playhead: 10))
    }

    @Test("A pass keeping up with the playhead goes on")
    func keepsUp() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 34, playhead: 30,
                                          inHand: { $0 < 34 })
        #expect(serves)
    }

    @Test("A pass that has not reached the playhead yet but is close goes on")
    func closeBehind() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 30 - MoviePlayPass.fallenBehindFrames,
                                          playhead: 30, inHand: { _ in false })
        #expect(serves)
    }

    @Test("A pass fallen well behind the playhead is started again where it is")
    func fallenBehind() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 29 - MoviePlayPass.fallenBehindFrames,
                                          playhead: 30, inHand: { _ in false })
        #expect(!serves)
    }

    @Test("A playhead that went back before the pass starts it again")
    func wentBack() {
        #expect(!MoviePlayPass.serves(running: 20...last, reached: 25, playhead: 12, inHand: { _ in true }))
    }

    @Test("A playhead back over ground the pass let go of starts it again")
    func backOverLostGround() {
        #expect(!MoviePlayPass.serves(running: 20...last, reached: 60, playhead: 30,
                                      inHand: { $0 > 50 }))
        #expect(MoviePlayPass.serves(running: 20...last, reached: 60, playhead: 30,
                                     inHand: { $0 > 25 }))
    }

    @Test("A frame the pass is about to reach is its to read")
    func coversAhead() {
        #expect(MoviePlayPass.covers(frame: 36, running: 20...last, reached: 34, playhead: 30))
        #expect(MoviePlayPass.covers(frame: 34, running: 20...last, reached: 34, playhead: 30))
    }

    @Test("A frame the pass already went by is not its to read")
    func notBehind() {
        #expect(!MoviePlayPass.covers(frame: 33, running: 20...last, reached: 34, playhead: 30))
    }

    @Test("A frame far past the playhead, across a cut, is read on its own")
    func notAcrossACut() {
        #expect(!MoviePlayPass.covers(frame: 90, running: 20...last, reached: 34, playhead: 30))
        #expect(MoviePlayPass.covers(frame: 30 + MoviePlayPass.aheadFrames, running: 20...last,
                                     reached: 34, playhead: 30))
    }

    @Test("A frame outside the pass is not its to read")
    func outside() {
        #expect(!MoviePlayPass.covers(frame: 5, running: 20...last, reached: 20, playhead: 20))
    }
}

@Suite("Where a one-pass read has got to")
struct MovieSweepGridReachTests {

    @Test("The next frame to fill starts at the first and moves as samples arrive")
    func next() {
        var grid = MovieSweepGrid(frames: 10...20)
        #expect(grid.nextFrame == 10)
        _ = grid.arrived(atMS: 330)
        _ = grid.arrived(atMS: 347)
        #expect(grid.nextFrame == 11)
    }
}

/// Playing across a cut stuck for most of a second
/// (`a-full-screen-recording-keeps-up-as-it-plays-acr`). Reproduced with the
/// Retina fixture cut at a quarter and at the middle, the middle deleted:
/// 3 of 20 looks late by up to 23 frames, and 6 of 20 by up to 20 with a
/// dissolve on the cut. The far side of a cut was read only once the playhead
/// got there, and a pass started there decodes from the key frame before it.
/// So the stretches about to come on are found ahead of time and a pass is
/// opened on each, read a few frames in and waiting.
@Suite("The stretches of a recording about to come on while it plays")
struct MoviePlayPointsTests {

    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 8000)

    private func frame(_ request: MovieFrameRequest) -> Int { movie.frameIndex(atSourceMS: request.sourceMS) }

    /// One clip in two pieces: 0 to 3s of the file, then 5s to 8s.
    private func cutDocument() throws -> (PhotonzDocument, UUID) {
        var document = PhotonzDocument.recording(movie, name: "Take 1")
        let id = try #require(document.layers.first).id
        document.updateLayer(id: id) {
            $0.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 3000),
                                                 ClipPiece(sourceInMS: 5000, lengthMS: 3000)],
                                        sourceLengthMS: 8000))
        }
        return (document, id)
    }

    @Test("A recording with no cut has only the frame under the playhead")
    func plain() {
        let document = PhotonzDocument.recording(movie, name: "Take 1")
        let points = document.moviePlayPoints(atTimeMS: 1000)
        #expect(points.now.map(frame) == [movie.frameIndex(atSourceMS: 1000)])
        #expect(points.coming.isEmpty)
    }

    @Test("The far side of a cut within reach is coming")
    func cutAhead() throws {
        let (document, _) = try cutDocument()
        let points = document.moviePlayPoints(atTimeMS: 3000 - MoviePlayPass.comingLeadMS + 200)
        #expect(points.now.count == 1)
        #expect(points.coming.map(frame) == [movie.frameIndex(atSourceMS: 5000)])
    }

    @Test("A cut further off than the lead is not coming yet")
    func cutFarOff() throws {
        let (document, _) = try cutDocument()
        let points = document.moviePlayPoints(atTimeMS: 3000 - MoviePlayPass.comingLeadMS - 200)
        #expect(points.coming.isEmpty)
    }

    @Test("A cut back to an earlier part of the recording is coming too")
    func cutBack() throws {
        var document = PhotonzDocument.recording(movie, name: "Take 1")
        let id = try #require(document.layers.first).id
        document.updateLayer(id: id) {
            $0.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 5000, lengthMS: 3000),
                                                 ClipPiece(sourceInMS: 0, lengthMS: 3000)],
                                        sourceLengthMS: 8000))
        }
        let points = document.moviePlayPoints(atTimeMS: 2500)
        #expect(points.coming.map(frame) == [0])
    }

    @Test("A dissolve's incoming shot is coming once, not again where the dissolve ends")
    func dissolveAhead() throws {
        var (document, id) = try cutDocument()
        let put = document.setClipTransition(id, atCut: 1,
                                             to: ClipTransition(kind: .dissolve, lengthMS: 1000))
        #expect(put)
        // The dissolve runs 2.5s to 3.5s; the shot coming in starts 4.5s into the file.
        let points = document.moviePlayPoints(atTimeMS: 1500)
        #expect(points.coming.map(frame) == [movie.frameIndex(atSourceMS: 4500)])
        // ...and once it is running, both shots are under the playhead.
        let during = document.moviePlayPoints(atTimeMS: 3000)
        #expect(during.now.count == 2)
        #expect(during.coming.isEmpty)
    }

    @Test("Playing out the last stretch, nothing is coming")
    func nothingAfterTheEnd() throws {
        let (document, _) = try cutDocument()
        #expect(document.moviePlayPoints(atTimeMS: 5800).coming.isEmpty)
    }
}

/// Looking a second and a half ahead every tick of the clock cost 22ms a tick
/// (debug build) on a ten-layer document with forty cuts, all of it on the
/// main actor. Remembered from tick to tick, each tick looks at the one new
/// moment entering the window.
@Suite("Looking ahead of a playing playhead from one tick to the next")
struct MoviePlayLookaheadTests {

    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 8000)

    private func cutDocument() throws -> PhotonzDocument {
        var document = PhotonzDocument.recording(movie, name: "Take 1")
        let id = try #require(document.layers.first).id
        document.updateLayer(id: id) {
            $0.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 3000),
                                                 ClipPiece(sourceInMS: 5000, lengthMS: 3000)],
                                        sourceLengthMS: 8000))
        }
        return document
    }

    @Test("Ticking through a cut gives what looking afresh gives, at every tick")
    func matchesAFreshLook() throws {
        let document = try cutDocument()
        var ahead = MoviePlayLookahead()
        for ms in stride(from: 0, through: 5900, by: 37) {
            let ticked = ahead.points(in: document, atTimeMS: ms)
            let fresh = document.moviePlayPoints(atTimeMS: ms)
            #expect(ticked.now == fresh.now, "now at \(ms)")
            #expect(ticked.coming == fresh.coming, "coming at \(ms)")
        }
    }

    @Test("Each tick looks at only the new moments entering the window")
    func cheap() throws {
        let document = try cutDocument()
        var ahead = MoviePlayLookahead()
        _ = ahead.points(in: document, atTimeMS: 0)
        let looked = ahead.looks
        _ = ahead.points(in: document, atTimeMS: 33)
        // The moment under the playhead, and one more at the far end.
        #expect(ahead.looks - looked <= 3)
    }

    @Test("A changed document or a jump is looked at afresh")
    func startsOver() throws {
        let document = try cutDocument()
        var ahead = MoviePlayLookahead()
        _ = ahead.points(in: document, atTimeMS: 0)
        #expect(ahead.points(in: document, atTimeMS: 2000).coming
                == document.moviePlayPoints(atTimeMS: 2000).coming)
        let plain = PhotonzDocument.recording(movie, name: "Take 1")
        #expect(ahead.points(in: plain, atTimeMS: 2033).coming.isEmpty)
        #expect(ahead.points(in: document, atTimeMS: 100).coming.isEmpty)
    }
}

@Suite("Which passes a playing playhead keeps, aims and opens")
struct MoviePlayPassPlanTests {

    private typealias Pass = MoviePlayPass.Running
    private let last = 239

    @Test("A pass keeping up with the playhead is aimed at it")
    func keeps() {
        let plan = MoviePlayPass.plan(now: [30], coming: [],
                                      passes: [Pass(running: 20...last, reached: 34, playhead: 29,
                                                    reach: MoviePlayPass.aheadFrames)],
                                      inHand: { _ in true })
        #expect(plan.aim == [0: .init(playhead: 30, reach: MoviePlayPass.aheadFrames)])
        #expect(plan.open.isEmpty)
    }

    @Test("The far side of a cut gets a pass of its own, read a few frames in")
    func primes() {
        let plan = MoviePlayPass.plan(now: [30], coming: [150],
                                      passes: [Pass(running: 20...last, reached: 34, playhead: 29,
                                                    reach: MoviePlayPass.aheadFrames)],
                                      inHand: { _ in true })
        #expect(plan.aim[0]?.playhead == 30)
        #expect(plan.open == [.init(playhead: 150, reach: MoviePlayPass.primeFrames)])
    }

    @Test("A pass already opened on the far side is kept as it is, not opened again")
    func keepsPrimed() {
        let passes = [Pass(running: 20...last, reached: 34, playhead: 29, reach: MoviePlayPass.aheadFrames),
                      Pass(running: 150...last, reached: 150, playhead: 150, reach: MoviePlayPass.primeFrames)]
        let plan = MoviePlayPass.plan(now: [30], coming: [150], passes: passes, inHand: { $0 < 40 })
        #expect(plan.aim[1] == .init(playhead: 150, reach: MoviePlayPass.primeFrames))
        #expect(plan.open.isEmpty)
    }

    @Test("Across the cut the opened pass takes the playhead and the old one stops")
    func crosses() {
        let passes = [Pass(running: 20...last, reached: 98, playhead: 89, reach: MoviePlayPass.aheadFrames),
                      Pass(running: 150...last, reached: 155, playhead: 150, reach: MoviePlayPass.primeFrames)]
        let plan = MoviePlayPass.plan(now: [150], coming: [], passes: passes, inHand: { _ in true })
        #expect(plan.aim == [1: .init(playhead: 150, reach: MoviePlayPass.aheadFrames)])
        #expect(plan.open.isEmpty)
    }

    @Test("Two shots of one recording on screen at once each get a pass")
    func dissolve() {
        let passes = [Pass(running: 0...last, reached: 80, playhead: 75, reach: MoviePlayPass.aheadFrames),
                      Pass(running: 136...last, reached: 141, playhead: 136, reach: MoviePlayPass.primeFrames)]
        let plan = MoviePlayPass.plan(now: [76, 137], coming: [], passes: passes, inHand: { _ in true })
        #expect(plan.aim == [0: .init(playhead: 76, reach: MoviePlayPass.aheadFrames),
                             1: .init(playhead: 137, reach: MoviePlayPass.aheadFrames)])
        #expect(plan.open.isEmpty)
    }

    @Test("Nothing to keep: a pass is opened where the playhead is")
    func opens() {
        let plan = MoviePlayPass.plan(now: [30], coming: [], passes: [], inHand: { _ in false })
        #expect(plan.aim.isEmpty)
        #expect(plan.open == [.init(playhead: 30, reach: MoviePlayPass.aheadFrames)])
    }

    @Test("No more passes are opened ahead than a recording may have")
    func bounded() {
        let plan = MoviePlayPass.plan(now: [30], coming: [90, 150, 200, 230], passes: [], inHand: { _ in false })
        #expect(plan.open.count == MoviePlayPass.passesPerRecording)
        #expect(plan.open.first?.playhead == 30)
    }

    @Test("A cut the running pass reaches anyway needs no pass of its own")
    func smallJump() {
        let plan = MoviePlayPass.plan(now: [30], coming: [35],
                                      passes: [Pass(running: 20...last, reached: 32, playhead: 29,
                                                    reach: MoviePlayPass.aheadFrames)],
                                      inHand: { $0 < 32 })
        #expect(plan.open.isEmpty)
    }

    @Test("A pass reaching a few frames in waits there")
    func primeWaits() {
        #expect(!MoviePlayPass.shouldWait(next: 150 + MoviePlayPass.primeFrames, playhead: 150,
                                          reach: MoviePlayPass.primeFrames))
        #expect(MoviePlayPass.shouldWait(next: 151 + MoviePlayPass.primeFrames, playhead: 150,
                                         reach: MoviePlayPass.primeFrames))
    }

    @Test("Each pass is given room in the budget for what it reads ahead")
    func budget() {
        #expect(MoviePlayPass.frameBudget(base: 16, reaches: []) == 16)
        #expect(MoviePlayPass.frameBudget(base: 16, reaches: [MoviePlayPass.aheadFrames]) == 16)
        let two = MoviePlayPass.frameBudget(base: 16, reaches: [MoviePlayPass.aheadFrames, MoviePlayPass.aheadFrames])
        #expect(two >= 2 * (MoviePlayPass.aheadFrames + 1) + MoviePlayPass.fallenBehindFrames)
    }
}

@Suite("Letting go of frames with more than one playhead in a recording")
struct MovieFrameFociTests {
    @Test("The frame let go is the one farthest from every place being played")
    func farthestFromAll() {
        let movie = UUID()
        let resident: [(movie: UUID, frame: Int)] = [(movie, 30), (movie, 150), (movie, 90), (movie, 31)]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: [30, 150]]) == 2)
    }

    @Test("Playing forwards, a frame gone by goes before one read ahead the same distance off")
    func behindGoesFirst() {
        let movie = UUID()
        // 26 is four behind the playhead on 30, 37 seven ahead of it: a frame
        // read ahead is about to be shown, one gone by is not.
        let resident: [(movie: UUID, frame: Int)] = [(movie, 37), (movie, 26), (movie, 31)]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: [30]], forward: true) == 1)
        // A hand that may turn round keeps both sides alike.
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: [30]]) == 0)
    }
}
