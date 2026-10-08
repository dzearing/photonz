import CoreGraphics
import Foundation

// A full-screen Retina recording keeps up while it plays
// (`a-full-screen-retina-recording-keeps-up-while-it`).
//
// Playing used to read each frame on its own, four at a time, the way a
// still playhead is read. Each of those reads seeks: it decodes from the key
// frame before it, and the four do not share the work. On the 3456x2234
// fixture that came to about 15 frames a second against the 30 the grid
// shows, so the picture fell further behind with every frame and held one up
// to half a second old (measured 2026-10-07: 90 frames in 6.0s that way, the
// same stretch read in one pass and every frame converted in 0.45s).
//
// So a playing playhead is fed by ONE pass over the recording from where it
// is, every frame decoded once, read at the size the canvas shows it and
// filed sharp. The pass keeps `aheadFrames` ahead of the playhead and waits
// there, so it never reads frames the window would only have to let go of,
// and it is started over wherever the playhead goes that it is not: a scrub
// while playing, a cut that jumps within the same recording, a machine so
// loaded the pass fell behind.
//
// A cut is the playhead going somewhere it is not, on purpose, and a pass
// started there decodes from the key frame before it: on the fixture cut at a
// quarter and at the middle, most of a second, so the picture stuck at every
// cut while the sound went on (`a-full-screen-recording-keeps-up-as-it-plays-acr`,
// 3 of 20 looks late by up to 23 frames; 6 of 20 by up to 20 across a
// dissolve). So the stretches about to come on are found `comingLeadMS` ahead
// (`PhotonzDocument.moviePlayPoints`) and a pass is opened on each, read
// `primeFrames` in and waiting, which then simply carries on when the playhead
// gets there. A dissolve between two parts of one recording is two of them at
// once, each with its own pass.

/// Which stretch of a recording a playing playhead reads in one pass, and
/// when that pass has stopped serving it.
public enum MoviePlayPass {

    /// How many grid frames ahead of the playhead a pass reads before it waits.
    /// A quarter of a second: the same reach exact reads had, well inside the
    /// sixteen frames a window keeps, so nothing read ahead is let go before
    /// it is shown.
    public static let aheadFrames = 8
    /// How far the pass may be behind the playhead before it is started over
    /// where the playhead is. A few frames: a start costs one decode from the
    /// key frame before it, which is cheaper than catching up a long way.
    public static let fallenBehindFrames = 4
    /// How many frames into a stretch about to come on a pass reads before it
    /// waits for the playhead to arrive. A few: the cost of a cut is getting
    /// the decoder to its first frame, and once there one pass outruns the
    /// clock.
    public static let primeFrames = 4
    /// How far ahead of the playhead a stretch about to come on is opened. A
    /// pass started on the far side of a cut decodes from the key frame before
    /// it, which is up to a couple of seconds of the recording; a second and a
    /// half of the clock covers that with room on a loaded machine.
    public static let comingLeadMS = 1500
    /// The most passes one recording reads at once: the stretch playing, the
    /// shot coming in over it during a dissolve, and the next cut.
    public static let passesPerRecording = 3

    /// The grid frames a pass for a playhead on `frame` reads: from there to
    /// the end of the recording. It waits, rather than stops, so a long play
    /// is one pass.
    public static func window(from frame: Int, movie: MovieRef) -> ClosedRange<Int> {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let from = min(max(0, frame), last)
        return from...last
    }

    /// Whether a pass whose next frame to fill is `next` is far enough ahead
    /// of a playhead on `playhead` to wait for it.
    public static func shouldWait(next: Int, playhead: Int, reach: Int = aheadFrames) -> Bool {
        next > playhead + reach
    }

    /// Whether the pass reading `running`, which has filled every frame
    /// before `reached`, still serves a playhead on `playhead`.
    ///
    /// Not when the playhead is outside it, nor when the pass has fallen more
    /// than `fallenBehindFrames` behind, nor when the playhead went back over
    /// ground the pass already read and the window has let that frame go.
    public static func serves(running: ClosedRange<Int>, reached: Int, playhead: Int,
                              inHand: (Int) -> Bool) -> Bool {
        guard running.contains(playhead) else { return false }
        if reached < playhead - fallenBehindFrames { return false }
        if playhead < reached, !inHand(playhead) { return false }
        return true
    }

    /// Whether the frame `frame` is the running pass's to read, so nothing
    /// reads it on its own: inside the pass, not yet gone by, and no further
    /// past the playhead than the pass will go. A frame further than that is
    /// across a cut and is read on its own.
    public static func covers(frame: Int, running: ClosedRange<Int>, reached: Int, playhead: Int,
                              reach: Int = aheadFrames) -> Bool {
        running.contains(frame) && frame >= reached && frame <= max(reached, playhead + reach)
    }

    // MARK: More than one pass in a recording

    /// A pass reading a recording: what it covers, the first frame it has not
    /// filled yet, and where it is aimed.
    public struct Running: Sendable, Equatable {
        public var running: ClosedRange<Int>
        public var reached: Int
        public var playhead: Int
        public var reach: Int

        public init(running: ClosedRange<Int>, reached: Int, playhead: Int, reach: Int) {
            self.running = running
            self.reached = reached
            self.playhead = playhead
            self.reach = reach
        }
    }

    /// Where a pass is aimed: the frame it keeps ahead of, and how far ahead.
    public struct Aim: Sendable, Equatable {
        public var playhead: Int
        public var reach: Int

        public init(playhead: Int, reach: Int) {
            self.playhead = playhead
            self.reach = reach
        }
    }

    /// What to do with one recording's passes this tick: the ones to keep,
    /// each aimed (by index into the passes asked about), and the ones to
    /// open. Every pass not kept is stopped.
    public struct Plan: Sendable, Equatable {
        public var aim: [Int: Aim] = [:]
        public var open: [Aim] = []
    }

    /// Which passes of one recording a playing playhead keeps, and which it
    /// opens: one for each frame under the playhead (two while a dissolve
    /// runs between parts of it), then one for each stretch `coming`, unless a
    /// pass kept already reaches it, up to `passesPerRecording`.
    public static func plan(now: [Int], coming: [Int], passes: [Running],
                            inHand: (Int) -> Bool) -> Plan {
        var plan = Plan()
        for frame in unique(now) {
            let serving = passes.indices.filter {
                plan.aim[$0] == nil
                    && serves(running: passes[$0].running, reached: passes[$0].reached,
                              playhead: frame, inHand: inHand)
            }
            let aim = Aim(playhead: frame, reach: aheadFrames)
            if let best = serving.min(by: { abs(passes[$0].reached - frame) < abs(passes[$1].reached - frame) }) {
                plan.aim[best] = aim
            } else {
                plan.open.append(aim)
            }
        }
        for frame in unique(coming) {
            let kept = plan.aim.contains { index, aim in
                reaches(frame, running: passes[index].running, reached: passes[index].reached,
                        aim: aim, inHand: inHand)
            }
            let opening = plan.open.contains { $0.playhead <= frame && frame <= $0.playhead + $0.reach }
            if kept || opening { continue }
            if let waiting = passes.indices.first(where: {
                plan.aim[$0] == nil
                    && reaches(frame, running: passes[$0].running, reached: passes[$0].reached,
                               aim: Aim(playhead: passes[$0].playhead, reach: passes[$0].reach),
                               inHand: inHand)
            }) {
                plan.aim[waiting] = Aim(playhead: passes[waiting].playhead, reach: passes[waiting].reach)
                continue
            }
            guard plan.aim.count + plan.open.count < passesPerRecording else { break }
            plan.open.append(Aim(playhead: frame, reach: primeFrames))
        }
        return plan
    }

    /// Whether a pass aimed at `aim` will have `frame` in hand without the
    /// playhead moving: inside it, within its reach, and not gone by and let go.
    private static func reaches(_ frame: Int, running: ClosedRange<Int>, reached: Int, aim: Aim,
                                inHand: (Int) -> Bool) -> Bool {
        running.contains(frame) && frame <= aim.playhead + aim.reach && (frame >= reached || inHand(frame))
    }

    private static func unique(_ frames: [Int]) -> [Int] {
        var seen = Set<Int>()
        return frames.filter { seen.insert($0).inserted }
    }

    /// How many sharp frames a window keeps while passes read: at least
    /// `base`, and room for every frame each pass reads ahead plus a few
    /// behind, so a frame read for a shot coming in is never let go to make
    /// room for the shot going out.
    public static func frameBudget(base: Int, reaches: [Int]) -> Int {
        guard reaches.count > 1 else { return base }
        return max(base, reaches.reduce(0) { $0 + $1 + 1 } + fallenBehindFrames)
    }
}

/// What a playing playhead needs read in each recording: the frames under it
/// now, and the first frame of each stretch about to come on.
public struct MoviePlayPoints: Sendable, Equatable {
    public var now: [MovieFrameRequest]
    public var coming: [MovieFrameRequest]

    public init(now: [MovieFrameRequest], coming: [MovieFrameRequest]) {
        self.now = now
        self.coming = coming
    }
}

extension PhotonzDocument {

    /// The frames under a playhead playing forwards at `ms`, and the first
    /// frame of every stretch of a recording that comes on within `leadMS`:
    /// the far side of a cut, the shot coming in over a dissolve, a clip that
    /// starts. A frame that carries on from one shown a frame earlier, in the
    /// same recording, is not a new stretch, so a dissolve's incoming shot is
    /// coming once and not again where the dissolve ends.
    ///
    /// Looked at afresh. A playing clock asks every tick, and keeps a
    /// `MoviePlayLookahead` so each tick only looks at what is new.
    public func moviePlayPoints(atTimeMS ms: Int, leadMS: Int = MoviePlayPass.comingLeadMS) -> MoviePlayPoints {
        var ahead = MoviePlayLookahead()
        return ahead.points(in: self, atTimeMS: ms, leadMS: leadMS)
    }
}

/// `PhotonzDocument.moviePlayPoints`, remembered from one tick of a playing
/// clock to the next: the stretch already looked over is kept, and each tick
/// looks only at the moments that have come into reach since. Looking the
/// whole second and a half again every tick cost 22ms a tick (debug build) on
/// ten layers and forty cuts. Started over when the document changes or the
/// playhead goes somewhere the last look did not lead.
public struct MoviePlayLookahead: Sendable {

    private var document: PhotonzDocument?
    /// The playhead last asked about, and the last moment looked at.
    private var playhead = 0
    private var lookedTo = 0
    /// What that last moment needed.
    private var last: [MovieFrameRequest] = []
    /// The stretches found coming on, and the moment each does.
    private var found: [(atMS: Int, request: MovieFrameRequest)] = []
    /// How many moments have been looked at, all told. What a test reads to
    /// tell a tick that looked again from one that did not.
    public private(set) var looks = 0

    public init() {}

    public mutating func points(in document: PhotonzDocument, atTimeMS ms: Int,
                                leadMS: Int = MoviePlayPass.comingLeadMS) -> MoviePlayPoints {
        let now = frames(in: document, atMS: ms)
        guard document.hasMovies else { return MoviePlayPoints(now: now, coming: []) }
        let step = MovieRef.frameStepMS
        if self.document != document || ms < playhead || ms > lookedTo {
            self.document = document
            lookedTo = ms
            last = now
            found = []
        }
        playhead = ms
        let end = min(ms + leadMS, document.lastDrawableTimeMS)
        while lookedTo + step <= end {
            let moment = lookedTo + step
            let frames = frames(in: document, atMS: moment)
            for request in frames {
                let index = request.movie.frameIndex(atSourceMS: request.sourceMS)
                let carriesOn = last.contains {
                    $0.movie.id == request.movie.id
                        && (0...MoviePlayPass.aheadFrames).contains(index - $0.movie.frameIndex(atSourceMS: $0.sourceMS))
                }
                guard !carriesOn else { continue }
                // Looked at a frame's length apart, the first look inside a
                // new stretch can be a frame into it, and a pass opened one
                // frame late is a pass the playhead lands in front of.
                let first = firstFrame(of: request, at: index, in: document, after: lookedTo, by: moment)
                if !found.contains(where: { $0.request.ref == first.request.ref }) { found.append(first) }
            }
            last = frames
            lookedTo = moment
        }
        found.removeAll { $0.atMS <= ms }
        return MoviePlayPoints(now: now, coming: found.map(\.request))
    }

    private mutating func frames(in document: PhotonzDocument, atMS ms: Int) -> [MovieFrameRequest] {
        looks += 1
        return document.movieFrames(atTimeMS: ms)
    }

    /// The first frame of the stretch `request` (seen at `index`, at
    /// `moment`) belongs to, and when it comes on, somewhere after `before`.
    private mutating func firstFrame(of request: MovieFrameRequest, at index: Int, in document: PhotonzDocument,
                                     after before: Int, by moment: Int) -> (atMS: Int, request: MovieFrameRequest) {
        func inStretch(_ ms: Int) -> MovieFrameRequest? {
            frames(in: document, atMS: ms).first {
                $0.layerID == request.layerID && $0.movie.id == request.movie.id
                    && (index - 2...index).contains($0.movie.frameIndex(atSourceMS: $0.sourceMS))
            }
        }
        var low = before, high = moment, found = request
        while high - low > 1 {
            let middle = (low + high) / 2
            if let earlier = inStretch(middle) {
                found = earlier
                high = middle
            } else {
                low = middle
            }
        }
        return (high, found)
    }
}
