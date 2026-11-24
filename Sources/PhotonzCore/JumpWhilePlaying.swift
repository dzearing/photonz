import Foundation

// Jumping back while a video plays never flickers between two frames
// (`jumping-back-while-a-video-plays-never-flickers`).
//
// The user clicked an earlier point on the timeline while a plain MP4 played,
// and for about half a second the picture swapped between two frames. A
// snapshot cannot see that, and nor can a look every half second: it is one
// picture in two, for a dozen pictures. So a walk keeps EVERY picture the
// canvas is handed after the jump, and for each clip on screen which frame
// its moment shows and which frame was drawn instead, and this reads them.
//
// What is allowed is a wait: the picture from before the jump held while the
// new place is read (every player does that), as long as it is short. What is
// not is the picture going back and forth in time once the new place is on
// screen, a frame from anywhere but the moment's own, or a picture that does
// not look like its moment.

/// What a playing playhead put on screen after it was moved, read picture by
/// picture.
public struct JumpPlayReading: Sendable, Equatable {

    /// One clip in one picture: which frame its moment shows, and which was
    /// drawn (nil when nothing of it was).
    public struct Frame: Sendable, Equatable {
        public var clip: String
        public var wanted: Int
        public var shown: Int?

        public init(clip: String, wanted: Int, shown: Int?) {
            self.clip = clip
            self.wanted = wanted
            self.shown = shown
        }
    }

    /// One picture the canvas was handed: its moment, its clips, and its mean
    /// difference (0 to 255) from a picture of that moment drawn the way the
    /// export draws it.
    public struct Look: Sendable, Equatable {
        public var momentMS: Int
        public var frames: [Frame]
        public var difference: Double
        /// When the canvas was handed it, on the wall clock. A jump while
        /// playing waits for its first frames with the playhead standing still,
        /// so the moment alone cannot tell a wait. The moment when not known.
        public var shownAtMS: Int

        public init(momentMS: Int, frames: [Frame], difference: Double, shownAtMS: Int? = nil) {
            self.momentMS = momentMS
            self.frames = frames
            self.difference = difference
            self.shownAtMS = shownAtMS ?? momentMS
        }
    }

    /// The longest the picture from before a jump may be held while the new
    /// place is read, by default: half a second, which is about what reading
    /// from a key frame two seconds back takes on a full-screen recording.
    public static let longestHoldMSByDefault = 500

    public let looks: [Look]
    /// The first picture (counted from 1) in which every clip shows its own
    /// moment's frame, or nil when none did.
    public let arrivedAtLook: Int?
    /// How long, from the first picture, until that one, on the wall clock.
    public let heldMS: Int?
    /// How many times a clip's picture went back in time, beyond the jump
    /// itself.
    public let reversals: Int
    /// Everything wrong, in plain words, one line each.
    public let problems: [String]

    /// - Parameters:
    ///   - looks: every picture after the jump, in the order the canvas got them.
    ///   - tolerance: the most a picture's difference may be once the new place is on screen.
    ///   - onTime: how many frames from its moment a picture may show and be on time
    ///     (`PlaybackKeepsUp.framesOnTime`).
    ///   - longestHoldMS: the longest wait for the new place.
    public init(looks: [Look], tolerance: Double, onTime: Int, longestHoldMS: Int = longestHoldMSByDefault) {
        self.looks = looks
        func onItsMoment(_ frame: Frame) -> Bool {
            frame.shown.map { abs($0 - frame.wanted) <= onTime } ?? false
        }
        let arrived = looks.firstIndex { $0.frames.allSatisfy(onItsMoment) }
        arrivedAtLook = arrived.map { $0 + 1 }
        heldMS = arrived.map { looks[$0].shownAtMS - (looks.first?.shownAtMS ?? 0) }
        var problems: [String] = []
        func at(_ index: Int) -> String {
            String(format: "picture %d at %.3fs", index + 1, Double(looks[index].momentMS) / 1000)
        }
        guard let arrived else {
            problems.append("the place jumped to never came on screen in \(looks.count) picture(s)")
            self.reversals = 0
            self.problems = problems
            return
        }
        if let held = heldMS, held > longestHoldMS {
            problems.append("the picture from before the jump was held \(held)ms before the new place came on, "
                + "at most \(longestHoldMS)ms is a wait")
        }
        // Back in time: stepping down onto the new place is the jump itself,
        // however many steps it takes (the frames a hand dragged over landing
        // one after another as it lets go). A step down once the new place is
        // on screen, or after the picture had gone forwards, is the picture
        // going back and forth.
        var backwards: [Int] = []
        let clips = Set(looks.flatMap { $0.frames.map(\.clip) })
        for clip in clips.sorted() {
            var last: Int?
            var wentForwards = false
            for (index, look) in looks.enumerated() {
                guard let shown = look.frames.first(where: { $0.clip == clip })?.shown else { continue }
                if let last, shown < last, index > arrived || wentForwards { backwards.append(index) }
                if let last, shown > last { wentForwards = true }
                last = shown
            }
        }
        reversals = backwards.count
        if !backwards.isEmpty {
            let which = Set(backwards).sorted().prefix(8).map { at($0) }.joined(separator: ", ")
            problems.append("the picture went backwards in time \(backwards.count) time(s) after the jump: \(which)")
        }
        // Once there, every clip shows its own moment: a frame from ahead of it
        // is a picture from somewhere else, and one behind is allowed only as
        // a playing picture is (`PlaybackKeepsUp`).
        var late: [Int] = []
        var behindMost = 0
        var elsewhere: [String] = []
        for index in looks.indices where index > arrived {
            for frame in looks[index].frames where !onItsMoment(frame) {
                guard let shown = frame.shown else {
                    elsewhere.append("\(at(index)) drew nothing of \(frame.clip)")
                    continue
                }
                if shown > frame.wanted {
                    elsewhere.append("\(at(index)) showed \(frame.clip) frame \(shown) for \(frame.wanted)")
                } else {
                    late.append(index)
                    behindMost = max(behindMost, frame.wanted - shown)
                }
            }
        }
        if !elsewhere.isEmpty {
            problems.append("after the new place came on, \(elsewhere.count) picture(s) showed a frame from "
                + "somewhere else: " + elsewhere.prefix(8).joined(separator: "; "))
        }
        let lateLooks = Set(late).sorted()
        if lateLooks.count > PlaybackKeepsUp.lateLooksAllowed
            || behindMost > PlaybackKeepsUp.framesBehindAllowed + onTime {
            problems.append("after the new place came on, \(lateLooks.count) picture(s) fell behind their moment, "
                + "up to \(behindMost) frame(s): " + lateLooks.prefix(8).map { at($0) }.joined(separator: ", "))
        }
        for index in looks.indices where index >= arrived && looks[index].difference > tolerance {
            problems.append(String(format: "%@ differs from its moment by %.1f, at most %.1f",
                                   at(index), looks[index].difference, tolerance))
        }
        self.problems = problems
    }
}

/// A walk step that plays, jumps the playhead while it plays, and reads every
/// picture after the jump (`JumpPlayReading`): `expectJumpWhilePlaying`.
public struct PlaytestJumpWhilePlaying: Sendable, Equatable {
    public var name: String
    /// Where playing starts, and how long it plays before the jump.
    public var fromSeconds: Double
    public var playForSeconds: Double
    /// Where the jump lands.
    public var toSeconds: Double
    public var rate: Double
    /// A hand dragging the playhead there on the ruler while it plays, rather
    /// than a click on the timeline.
    public var drag: Bool
    /// How long after the jump every picture is kept.
    public var watchSeconds: Double
    public var tolerance: Double
    public var longestHoldMS: Int

    public init(name: String, fromSeconds: Double, playForSeconds: Double, toSeconds: Double, rate: Double,
                drag: Bool, watchSeconds: Double, tolerance: Double, longestHoldMS: Int) {
        self.name = name
        self.fromSeconds = fromSeconds
        self.playForSeconds = playForSeconds
        self.toSeconds = toSeconds
        self.rate = rate
        self.drag = drag
        self.watchSeconds = watchSeconds
        self.tolerance = tolerance
        self.longestHoldMS = longestHoldMS
    }
}

extension MovieFramesInHand.Travel {

    /// Which way the playhead is going once it is put on `landing` from
    /// `from`. At rest, or under a hand, the way it was moved. While a clock
    /// plays it (`clockRate`, negative backwards) and no hand holds it, the
    /// clock's way: it plays on from where it landed.
    ///
    /// Taken from the move alone, a click back on the timeline while it
    /// played forwards left it going backwards for as long as it then played:
    /// nothing read ahead of it, and each frame not read yet was stood in for
    /// from the place it had left, so the picture swapped between the new
    /// place and the old one (2026-11-24).
    public static func afterMove(from: Int, to landing: Int, clockRate: Double?, handHolds: Bool) -> Self {
        if let clockRate, clockRate != 0, !handHolds { return clockRate < 0 ? .backward : .forward }
        return landing < from ? .backward : .forward
    }

    /// ...and once the hand lets go: the clock's way if one plays, else the
    /// way the hand last went.
    public static func whenHandLetsGo(clockRate: Double?, handWent: Self) -> Self {
        guard let clockRate, clockRate != 0 else { return handWent }
        return clockRate < 0 ? .backward : .forward
    }
}
