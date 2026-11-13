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

    // At 8x forwards the playhead moves about four grid frames a refresh, so a
    // pass eight ahead and dropped four behind was started over from its key
    // frame again and again, and on the five minute Retina talk the picture
    // held one up to 7 frames behind at 11 of 24 looks (2026-11-13). It reads
    // and keeps what playing backwards at 8x does: every third frame, three
    // times as far ahead, dropped three times as far behind.
    @Test("At 8x forwards a pass reaches three times as far, keeps every third frame and is let fall further behind")
    func eightTimesForwards() {
        #expect(MoviePlayPass.reach(speed: 1) == MoviePlayPass.aheadFrames)
        #expect(MoviePlayPass.reach(speed: 4) == MoviePlayPass.aheadFrames)
        #expect(MoviePlayPass.reach(speed: 8) == MoviePlayPass.aheadFrames * 3)
        #expect(MoviePlayPass.fallenBehind(speed: 1) == MoviePlayPass.fallenBehindFrames)
        #expect(MoviePlayPass.fallenBehind(speed: 8) == MoviePlayPass.fallenBehindFrames * 3)
        #expect(MoviePlayPass.keeps(frame: 31, speed: 4))
        #expect(MoviePlayPass.keeps(frame: 30, speed: 8))
        #expect(!MoviePlayPass.keeps(frame: 31, speed: 8))
        // Ten behind serves at 8x and not at 1x.
        #expect(MoviePlayPass.serves(running: 20...last, reached: 40, playhead: 50, inHand: { _ in true }, speed: 8))
        #expect(!MoviePlayPass.serves(running: 20...last, reached: 40, playhead: 50, inHand: { _ in true }))
        let plan = MoviePlayPass.plan(now: [50], coming: [],
                                      passes: [Pass(running: 20...last, reached: 40, playhead: 46,
                                                    reach: MoviePlayPass.reach(speed: 8))],
                                      inHand: { _ in true }, speed: 8)
        #expect(plan.aim == [0: .init(playhead: 50, reach: MoviePlayPass.reach(speed: 8))])
        #expect(plan.open.isEmpty)
    }

    // At 8x only every third frame is kept, so the frame under the playhead
    // is in hand two times in three only as the kept one before it. Asking
    // for the playhead's own frame called a pass that was ahead of the
    // playhead lost and started it over from its key frame, about every
    // other refresh on the six minute reference edit (traced 2026-11-13).
    @Test("At 8x a pass ahead of the playhead serves it when the kept frame it shows is in hand")
    func eightTimesServesOnTheKeptFrame() {
        let kept: (Int) -> Bool = { $0 % 3 == 0 }
        #expect(MoviePlayPass.serves(running: 1184...last + 2000, reached: 1200, playhead: 1193,
                                     inHand: kept, speed: 8))
        #expect(MoviePlayPass.serves(running: 1184...last + 2000, reached: 1218, playhead: 1217,
                                     inHand: kept, speed: 8))
        // A kept frame the pass read a moment ago may still be on its way to
        // the window: 1368 read, the pass at 1370, the playhead on 1369.
        #expect(MoviePlayPass.serves(running: 1184...last + 2000, reached: 1370, playhead: 1369,
                                     inHand: { $0 % 3 == 0 && $0 < 1368 }, speed: 8))
        // ...but one well behind what it read and let go starts it over.
        #expect(!MoviePlayPass.serves(running: 1184...last + 2000, reached: 1260, playhead: 1217,
                                      inHand: { $0 != 1215 && $0 % 3 == 0 }, speed: 8))
    }

    // A pass started over where the playhead is decodes from the key frame
    // before it, which took 25 to 90ms on the reference edit: 6 to 22 grid
    // frames at 8x. Opened under the playhead it was already behind when its
    // first frame came, was started over again, and the picture stuck up to
    // 177 frames behind (2026-11-13). Above double speed, which is silent,
    // the new pass opens that far ahead and serves the playhead on its way.
    @Test("Above 2x a pass that fell behind is started over ahead of the playhead, and serves it on the way")
    func fastRestartOpensAhead() {
        #expect(MoviePlayPass.startLead(speed: 1) == 0)
        #expect(MoviePlayPass.startLead(speed: 2) == 0)
        let four = MoviePlayPass.startLead(speed: 4), eight = MoviePlayPass.startLead(speed: 8)
        #expect(four >= 18 && four < eight)
        #expect(eight >= 36 && eight % 3 == 0)
        let behind = Pass(running: 1184...2000, reached: 1233, playhead: 1240, reach: MoviePlayPass.reach(speed: 8))
        let plan = MoviePlayPass.plan(now: [1249], coming: [], passes: [behind],
                                      inHand: { _ in true }, speed: 8)
        #expect(plan.aim.isEmpty)
        #expect(plan.open == [.init(playhead: 1249 + eight, reach: MoviePlayPass.reach(speed: 8))])
        // The next tick, before the new pass has its first frame, keeps it
        // and aims it at its own start, so it reads rather than waits.
        let opened = Pass(running: (1249 + eight)...2000, reached: 1249 + eight,
                          playhead: 1249 + eight, reach: MoviePlayPass.reach(speed: 8))
        let next = MoviePlayPass.plan(now: [1265], coming: [], passes: [opened],
                                      inHand: { _ in false }, speed: 8)
        #expect(next.open.isEmpty)
        #expect(next.aim == [0: .init(playhead: 1249 + eight, reach: MoviePlayPass.reach(speed: 8))])
        // Once the playhead is in it, it is aimed at the playhead again.
        let caught = MoviePlayPass.plan(now: [1300], coming: [],
                                        passes: [Pass(running: (1249 + eight)...2000, reached: 1310,
                                                      playhead: 1249 + eight, reach: 24)],
                                        inHand: { _ in true }, speed: 8)
        #expect(caught.aim == [0: .init(playhead: 1300, reach: MoviePlayPass.reach(speed: 8))])
        // At 2x and below, with sound, a pass still starts where the playhead is.
        let slow = MoviePlayPass.plan(now: [100], coming: [],
                                      passes: [Pass(running: 20...last, reached: 40, playhead: 90, reach: 8)],
                                      inHand: { _ in true }, speed: 2)
        #expect(slow.open == [.init(playhead: 100, reach: MoviePlayPass.reach(speed: 2))])
    }

    @Test("A pass opened for the playhead with nothing reading there yet starts under it, at any speed")
    func firstPassStartsUnderThePlayhead() {
        let plan = MoviePlayPass.plan(now: [100], coming: [], passes: [], inHand: { _ in false }, speed: 8)
        #expect(plan.open == [.init(playhead: 100, reach: MoviePlayPass.reach(speed: 8))])
    }

    // The far side of a cut was opened a second and a half of the edit
    // ahead, which at 8x is under 0.2s of the clock, and read four frames in:
    // at 8x that is one kept frame (2026-11-13).
    @Test("Faster than 1x a cut coming up is looked for as far ahead in the clock, and primed by the stride")
    func comingScalesWithSpeed() {
        #expect(MoviePlayPass.comingLead(speed: 1) == MoviePlayPass.comingLeadMS)
        #expect(MoviePlayPass.comingLead(speed: 0.25) == MoviePlayPass.comingLeadMS)
        #expect(MoviePlayPass.comingLead(speed: 8) == MoviePlayPass.comingLeadMS * 8)
        let plan = MoviePlayPass.plan(now: [30], coming: [150], passes: [], inHand: { _ in false }, speed: 8)
        #expect(plan.open.last == .init(playhead: 150, reach: MoviePlayPass.primeFrames * 3))
    }

    // The far side of a cut primed at 8x reads past its first frame without
    // keeping it (287 is not a third), so asking whether that frame was in
    // hand called the pass useless, and it was stopped and opened again on
    // every tick until the playhead got there (traced 2026-11-13).
    @Test("At 8x a primed pass on the far side of a cut is kept while it waits")
    func eightTimesPrimedPassIsKept() {
        let primed = Pass(running: 287...2000, reached: 300, playhead: 287, reach: MoviePlayPass.prime(speed: 8))
        let plan = MoviePlayPass.plan(now: [1200], coming: [287],
                                      passes: [Pass(running: 1100...2000, reached: 1210, playhead: 1200, reach: 24), primed],
                                      inHand: { $0 % 3 == 0 }, speed: 8)
        #expect(plan.open.isEmpty)
        #expect(plan.aim[1] == .init(playhead: 287, reach: MoviePlayPass.prime(speed: 8)))
        // ...and while its first frame, not a kept one, is the only one read.
        let started = Pass(running: 542...2000, reached: 543, playhead: 542, reach: MoviePlayPass.prime(speed: 8))
        let next = MoviePlayPass.plan(now: [1200], coming: [542],
                                      passes: [Pass(running: 1100...2000, reached: 1210, playhead: 1200, reach: 24), started],
                                      inHand: { $0 % 3 == 0 && $0 < 542 || $0 > 1000 }, speed: 8)
        #expect(next.open.isEmpty)
    }

    // Between the playhead and a pass started over ahead of it, nothing is
    // read on its own: each of those reads decodes from its key frame on the
    // lanes the new pass needs, and its first frame came 200 to 290ms late
    // with them (traced 2026-11-13). The picture holds the last frame in
    // hand for the start-up instead.
    @Test("Above 2x the frames a pass started over ahead skips are not read on their own")
    func fastRestartGapIsCovered() {
        let lead = MoviePlayPass.startLead(speed: 8)
        let start = 1300
        #expect(MoviePlayPass.covers(frame: start - 3, running: start...2000, reached: start,
                                     playhead: start - 20, reach: 24, speed: 8))
        #expect(!MoviePlayPass.covers(frame: start - lead - 3, running: start...2000, reached: start,
                                      playhead: start - lead - 3, reach: 24, speed: 8))
        #expect(!MoviePlayPass.covers(frame: start - 3, running: start...2000, reached: start,
                                      playhead: start - 20, reach: 8, speed: 1))
    }

    @Test("Above 2x a pass or frame read at another size still serves; at 2x and below it does not")
    func anySizeAtSpeed() {
        #expect(!MoviePlayPass.anySizeServes(speed: 1))
        #expect(!MoviePlayPass.anySizeServes(speed: 2))
        #expect(MoviePlayPass.anySizeServes(speed: 4))
        #expect(MoviePlayPass.anySizeServes(speed: 8))
        #expect(!MoviePlayPass.skipsUnreferenced(speed: 2))
        #expect(MoviePlayPass.skipsUnreferenced(speed: 4))
    }

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
