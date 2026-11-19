import Foundation

/// The numbers the speed walk takes on the reference edit, and the arithmetic
/// that turns raw looks into them (task
/// `a-speed-walk-measures-the-long-reference-edit-th`).
///
/// Every later video speed fix is judged by these numbers, so they are taken
/// the way a person meets the problem: frames due against frames shown while
/// it plays (and per transition, so a dropped frame is pinned to the cut it
/// happened at), how many display frames the picture trails a hand on the
/// playhead, the longest main thread pass an edit causes while it plays, the
/// display's frame times while the timeline scrolls and zooms, memory over a
/// long session, and the time an export takes.
///
/// The probe takes the looks (`PlaytestHarness`, the `speed` step); this file
/// only counts, so the counting is tested. One run is one `SpeedRun`, written
/// as `speed.json`; `SpeedCompare` sets two side by side and says which
/// numbers got worse than a baseline by more than a stated margin.
public enum SpeedWalk {

    // MARK: - Playing

    /// One look at a playing document, taken once per display refresh.
    public struct PlaySample: Equatable, Sendable {
        /// When the look was taken, on any steady clock, in milliseconds.
        public var wallMS: Double
        /// Where the playhead was.
        public var playheadMS: Int
        /// The moment of the picture the canvas was showing, nil before the
        /// first one came in.
        public var shownMS: Int?

        public init(wallMS: Double, playheadMS: Int, shownMS: Int?) {
            self.wallMS = wallMS
            self.playheadMS = playheadMS
            self.shownMS = shownMS
        }
    }

    /// What one stretch of playing came to.
    public struct PlayTally: Codable, Equatable, Sendable {
        /// "whole" for the whole run, or the transition it covers
        /// ("dissolve at 0:42.0").
        public var label: String
        /// How long the stretch lasted, in seconds of the document.
        public var seconds: Double
        /// How many pictures the app's own clock promises over the stretch
        /// (one every `MovieRef.frameStepMS`).
        public var framesDue: Int
        /// How many different moments the canvas actually showed.
        public var framesShown: Int
        /// Due less shown: the pictures a person never saw.
        public var dropped: Int
        /// The longest wait between one new picture and the next, which a
        /// person sees as the picture sticking.
        public var worstGapMS: Double
        /// For the whole run, how long after Space the first new picture came
        /// on screen: a start that takes a while, not a frame lost (nil for a
        /// transition, and in runs from before 2026-11-19).
        public var firstPictureMS: Double?

        public init(label: String, seconds: Double, framesDue: Int, framesShown: Int,
                    dropped: Int, worstGapMS: Double, firstPictureMS: Double? = nil) {
            self.label = label
            self.seconds = seconds
            self.framesDue = framesDue
            self.framesShown = framesShown
            self.dropped = dropped
            self.worstGapMS = worstGapMS
            self.firstPictureMS = firstPictureMS
        }
    }

    /// A stretch of the document worth its own numbers: a transition.
    public struct Span: Equatable, Sendable {
        public var label: String
        public var range: Range<Int>

        public init(label: String, range: Range<Int>) {
            self.label = label
            self.range = range
        }
    }

    /// One new picture: when it arrived, the moment it showed, and where the
    /// playhead was at the look before it and at it.
    private struct Arrival {
        var wallMS: Double
        var shownMS: Int
        var playheadMS: Int
    }

    /// The looks where a new moment came on screen, the first look included
    /// as the picture that was already up.
    private static func arrivals(_ samples: [PlaySample]) -> [Arrival] {
        var out: [Arrival] = []
        var last: Int?
        for sample in samples {
            guard let shown = sample.shownMS else { continue }
            if shown != last {
                out.append(Arrival(wallMS: sample.wallMS, shownMS: shown, playheadMS: sample.playheadMS))
                last = shown
            }
        }
        return out
    }

    /// The moments a person never saw, as the document times they were due
    /// at: the ones the picture jumped over between two new pictures, and
    /// the ones the playhead passed after the last new picture. The clock
    /// ticks about once a `frameStepMS` but not on a grid of it (each picture
    /// is the playhead's own moment at its tick), so a jump is counted by how
    /// many steps it spans, and the one picture still in flight when the
    /// stretch ends is not lost. Until 2026-11-19 frames due were the wall
    /// clock over the step, and a run that showed every moment read one
    /// dropped a minute: the start's first tick and the last picture in
    /// flight (pass 18 of `a-long-edit-with-transitions-plays-scrubs-and-ed`).
    private static func missedMoments(_ came: [Arrival], end: PlaySample, stepMS: Int) -> [Int] {
        var out: [Int] = []
        func steps(_ from: Int, _ to: Int) -> Int {
            Int((Double(to - from) / Double(stepMS)).rounded())
        }
        for (index, (before, after)) in zip(came, came.dropFirst()).enumerated() {
            // The clock starts at Space and its first tick lands a little
            // more than a step after: the first jump gets one step of slack,
            // and how long it took is the run's first picture time.
            let span = steps(before.shownMS, after.shownMS) - (index == 0 ? 1 : 0)
            guard span > 1 else { continue }
            out += (1 ..< span).map { before.shownMS + $0 * (after.shownMS - before.shownMS) / span }
        }
        if let last = came.last {
            let span = steps(last.shownMS, end.playheadMS)
            if span > 1 { out += (1 ..< span).map { last.shownMS + $0 * stepMS } }
        }
        return out
    }

    /// Where in the document the run's dropped frames were due, to say in a
    /// walk's line which cut or clip lost them.
    public static func droppedMoments(_ samples: [PlaySample], frameStepMS: Int) -> [Int] {
        guard let last = samples.last, frameStepMS > 0 else { return [] }
        return missedMoments(arrivals(samples), end: last, stepMS: frameStepMS)
    }

    /// The whole run: shown as every new moment after the first look, dropped
    /// as every moment missed, plus the ticks a clock that fell behind the
    /// wall never made (one tick of slack, since the playhead moves only on
    /// its ticks), and the longest wait between two new pictures.
    public static func tally(_ samples: [PlaySample], frameStepMS: Int) -> PlayTally {
        guard let first = samples.first, let last = samples.last, frameStepMS > 0 else {
            return PlayTally(label: "whole", seconds: 0, framesDue: 0, framesShown: 0, dropped: 0, worstGapMS: 0)
        }
        let wall = max(0, last.wallMS - first.wallMS)
        let came = arrivals(samples)
        // The picture up at the first look was not shown BY this stretch.
        let shown = max(0, came.count - (first.shownMS == nil ? 0 : 1))
        let behindMS = wall - Double(last.playheadMS - first.playheadMS)
        let clockLost = max(0, Int(((behindMS - Double(frameStepMS)) / Double(frameStepMS)).rounded(.down)))
        let dropped = missedMoments(came, end: last, stepMS: frameStepMS).count + clockLost
        var worst = 0.0
        var previous = first.wallMS
        for arrival in came {
            worst = max(worst, arrival.wallMS - previous)
            previous = arrival.wallMS
        }
        worst = max(worst, last.wallMS - previous)
        let firstNew = came.first { $0.shownMS != first.shownMS }.map { $0.wallMS - first.wallMS }
        return PlayTally(label: "whole", seconds: wall / 1000, framesDue: shown + dropped, framesShown: shown,
                         dropped: dropped, worstGapMS: worst, firstPictureMS: firstNew)
    }

    /// One transition: shown as the different moments inside it that came on
    /// screen, dropped as the moments inside it the picture missed, and the
    /// longest wait between two new pictures while the playhead was crossing
    /// it, so a stall that froze the picture over a cut is charged to that
    /// cut even when no look landed inside it.
    public static func tally(_ samples: [PlaySample], over span: Span, frameStepMS: Int) -> PlayTally {
        let length = span.range.count
        let came = arrivals(samples)
        let shown = Set(came.map(\.shownMS).filter { span.range.contains($0) }).count
        let dropped = frameStepMS > 0 && !samples.isEmpty
            ? missedMoments(came, end: samples[samples.count - 1], stepMS: frameStepMS)
                .filter { span.range.contains($0) }.count
            : 0
        var worst = 0.0
        var previous: Arrival?
        for arrival in came {
            defer { previous = arrival }
            guard let before = previous else { continue }
            // The playhead went from where it was at the last new picture to
            // where it is at this one: the stretch the wait was spent on.
            let lo = min(before.playheadMS, arrival.playheadMS)
            let hi = max(before.playheadMS, arrival.playheadMS)
            if lo < span.range.upperBound, hi >= span.range.lowerBound {
                worst = max(worst, arrival.wallMS - before.wallMS)
            }
        }
        // And from the last new picture to the end of the stretch, which on
        // an hour-long edit was the whole stretch: no new picture at all.
        if let lastArrival = came.last, let end = samples.last {
            let lo = min(lastArrival.playheadMS, end.playheadMS)
            let hi = max(lastArrival.playheadMS, end.playheadMS)
            if lo < span.range.upperBound, hi >= span.range.lowerBound {
                worst = max(worst, end.wallMS - lastArrival.wallMS)
            }
        }
        return PlayTally(label: span.label, seconds: Double(length) / 1000, framesDue: shown + dropped,
                         framesShown: shown, dropped: dropped, worstGapMS: worst)
    }

    /// Every transition on the document's picture tracks, in time order,
    /// labelled by its kind and where its cut is ("dissolve at 0:42.0").
    public static func transitionSpans(of doc: PhotonzDocument) -> [Span] {
        let byID = Dictionary(doc.timelineClipLayers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var spans: [Span] = []
        for track in doc.timelineTracks where track.kind == .video {
            for point in doc.editPoints(onTrack: track.id) {
                guard let transition = byID[point.incoming]?.arrivalTransition, transition.lengthMS > 0 else { continue }
                let length = transition.lengthMS
                let start: Int
                switch transition.alignment {
                case .before: start = point.atMS - length
                case .across: start = point.atMS - length / 2
                case .after: start = point.atMS
                }
                spans.append(Span(label: "\(transition.kind.title.lowercased()) at \(clock(point.atMS))",
                                  range: start..<(start + length)))
            }
        }
        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// "1:02.5": minutes, seconds and a tenth.
    public static func clock(_ ms: Int) -> String {
        let tenths = max(0, ms) / 100
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    // MARK: - Scrubbing

    /// A hand dragging the playhead end to end at one speed.
    public struct ScrubTally: Codable, Equatable, Sendable {
        /// "slow", "medium" or "fling", end to end, or "hunt", ten seconds of
        /// it (`PlaytestSpeedMeasure.scrubSpan`).
        public var speed: String
        /// How many display frames the drag took.
        public var frames: Int
        /// How many display frames the picture trailed the hand: the middle
        /// look and the worst.
        public var lagMedianFrames: Int
        public var lagWorstFrames: Int
        /// The same, counting a picture only once it is drawn from the very
        /// frames the moment under the hand shows. The canvas answers a move
        /// at once with the frame nearest in hand while the right one is read
        /// (`MovieFramesInHand`), and that picture carries the hand's moment,
        /// so the lag above counts it as caught up. Nil in a baseline written
        /// before 2026-11-17, which does not judge it.
        public var frameLagMedianFrames: Int?
        public var frameLagWorstFrames: Int?
        /// How many display frames behind the hand the recording on screen
        /// is, stand-ins and all: the refreshes since the hand was on the
        /// frames the picture is actually drawn from (`sightLags`). What a
        /// person sees: a stand-in one frame off reads as nearly caught up,
        /// one from a second of film away as far behind. Nil in a baseline
        /// written before 2026-11-17's second pass, which does not judge it.
        public var sightLagMedianFrames: Int?
        public var sightLagWorstFrames: Int?
        /// The longest wait between two display refreshes during the drag.
        public var worstFrameMS: Double
        /// How many looks the app answered over the drag, one per refresh it
        /// was free for: `frames` or a few more for an app that keeps up.
        public var movesMade: Int
        /// How long the drag took, against the `frames` refreshes it would
        /// take a display that kept up.
        public var seconds: Double

        public init(speed: String, frames: Int, lagMedianFrames: Int, lagWorstFrames: Int, worstFrameMS: Double,
                    movesMade: Int? = nil, seconds: Double = 0) {
            self.speed = speed
            self.frames = frames
            self.movesMade = movesMade ?? frames
            self.seconds = seconds
            self.lagMedianFrames = lagMedianFrames
            self.lagWorstFrames = lagWorstFrames
            self.worstFrameMS = worstFrameMS
        }
    }

    /// The middle and the worst of a list of lags, both zero for none.
    public static func lagStats(_ lags: [Int]) -> (median: Int, worst: Int) {
        guard !lags.isEmpty else { return (0, 0) }
        let sorted = lags.sorted()
        return (sorted[sorted.count / 2], sorted[sorted.count - 1])
    }

    /// How far the recording on screen was from the hand at each look, in
    /// display refreshes, by the frames the picture is drawn from: the time
    /// between the look and the nearest moment of the drag the hand was on a
    /// frame, before the look or after it (a stand-in from just ahead of the
    /// hand, read before it got there, is as near as one just behind), the
    /// farthest of them when a picture is drawn from several. A frame the
    /// hand was never on during the drag (a stand-in left from before it) is
    /// as far away as the drag is long so far. A look whose picture holds no
    /// frame of a recording (`drawn[i]` nil or empty) judges nothing and is
    /// left out.
    ///
    /// `needed[i]` is the frames the hand's moment needed before look `i`,
    /// `handAtMS[i]` when the hand was put there, `atMS[i]` when the look was
    /// taken and `drawn[i]` the frames the picture on screen then was drawn
    /// from.
    public static func sightLags(needed: [[UUID]], handAtMS: [Double], drawn: [Set<UUID>?], atMS: [Double],
                                 refreshMS: Double) -> [Int] {
        var when: [UUID: [Double]] = [:]
        for index in needed.indices where index < handAtMS.count {
            for frame in needed[index] { when[frame, default: []].append(handAtMS[index]) }
        }
        var lags: [Int] = []
        let interval = max(0.001, refreshMS)
        let first = handAtMS.first ?? 0
        for index in drawn.indices where index < atMS.count {
            guard let frames = drawn[index], !frames.isEmpty else { continue }
            let now = atMS[index]
            var apart: Double = 0
            for frame in frames {
                let visits = when[frame] ?? []
                let nearest = visits.map { abs(now - $0) }.min() ?? (now - first)
                apart = max(apart, nearest)
            }
            lags.append(max(0, Int((apart / interval).rounded())))
        }
        return lags
    }

    /// Every grid moment a hand crossed on its way through `hand` (where it
    /// put the playhead at each look, `handAtMS` when), each timed in
    /// proportion between the two moves either side of it, so a frame it
    /// passed over between two refreshes has a time too (`sightLags`). Each
    /// move's own moment is kept as it was; a move that stays put adds one.
    public static func handPath(hand: [Int], handAtMS: [Double], stepMS: Int) -> [(momentMS: Int, atMS: Double)] {
        let count = min(hand.count, handAtMS.count)
        guard count > 0 else { return [] }
        var path: [(momentMS: Int, atMS: Double)] = [(hand[0], handAtMS[0])]
        let step = max(1, stepMS)
        for index in 1..<max(1, count) where index < count {
            let from = hand[index - 1], to = hand[index]
            let fromAt = handAtMS[index - 1], toAt = handAtMS[index]
            if from != to {
                let way = to > from ? step : -step
                var moment = from + way
                while (way > 0 && moment < to) || (way < 0 && moment > to) {
                    let share = Double(moment - from) / Double(to - from)
                    path.append((moment, fromAt + share * (toAt - fromAt)))
                    moment += way
                }
            }
            path.append((to, toAt))
        }
        return path
    }

    /// How many display frames behind the picture was at each look: the
    /// time since the hand put the playhead on the moment the picture shows,
    /// in refreshes of the display, so a look the main thread held up for
    /// half a second counts the sixty refreshes the person sat through and
    /// not one. A picture that arrives at the very next refresh is one frame
    /// behind, which is as close as a display can be. A picture of a moment
    /// the hand never visited (or none at all) is as far behind as the drag
    /// is long so far.
    ///
    /// `hand[i]` is where the hand put the playhead before look `i`,
    /// `handAtMS[i]` when, `atMS[i]` when the look was taken and `shown[i]`
    /// the moment of the picture then.
    public static func scrubLags(hand: [Int], handAtMS: [Double], shown: [Int?], atMS: [Double],
                                 refreshMS: Double) -> [Int] {
        var lastAt: [Int: Double] = [:]
        var lags: [Int] = []
        let interval = max(0.001, refreshMS)
        let first = handAtMS.first ?? 0
        for index in hand.indices where index < atMS.count && index < handAtMS.count {
            lastAt[hand[index]] = handAtMS[index]
            let since: Double
            if index < shown.count, let moment = shown[index], let at = lastAt[moment] {
                since = atMS[index] - at
            } else {
                since = atMS[index] - first
            }
            lags.append(max(0, Int((since / interval).rounded())))
        }
        return lags
    }

    // MARK: - Frame times

    /// The display's refreshes while something moved: how far apart they
    /// came, against the display's own interval.
    public struct FrameTimes: Codable, Equatable, Sendable {
        public var label: String
        public var frames: Int
        public var refreshMS: Double
        public var medianMS: Double
        public var p95MS: Double
        public var worstMS: Double
        /// Refreshes that came more than half an interval late: a frame the
        /// display had to show twice.
        public var late: Int

        public init(label: String, frames: Int, refreshMS: Double, medianMS: Double, p95MS: Double,
                    worstMS: Double, late: Int) {
            self.label = label
            self.frames = frames
            self.refreshMS = refreshMS
            self.medianMS = medianMS
            self.p95MS = p95MS
            self.worstMS = worstMS
            self.late = late
        }
    }

    /// Frame times from the moments of each refresh.
    public static func frameTimes(_ label: String, refreshesAtMS: [Double], refreshMS: Double) -> FrameTimes {
        let gaps = zip(refreshesAtMS.dropFirst(), refreshesAtMS).map { $0 - $1 }.sorted()
        guard !gaps.isEmpty else {
            return FrameTimes(label: label, frames: 0, refreshMS: refreshMS, medianMS: 0, p95MS: 0, worstMS: 0, late: 0)
        }
        let p95 = gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
        return FrameTimes(label: label, frames: gaps.count, refreshMS: refreshMS, medianMS: gaps[gaps.count / 2],
                          p95MS: p95, worstMS: gaps[gaps.count - 1],
                          late: gaps.filter { $0 > refreshMS * 1.5 }.count)
    }

    // MARK: - Editing, memory, export, sound

    /// Where the memory walk's hand takes the playhead, once every half
    /// minute: the same places on every run, so two runs play and scrub the
    /// same parts of the edit and their memory can be set side by side. Each
    /// is far enough from the end to play on for half a minute. Picked at
    /// random by every run until 2026-11-16, when one run's second minute sat
    /// 5 percent under the next run's for no reason but where it had been.
    public static func memoryScrubPlaces(count: Int, lengthMS: Int) -> [Int] {
        var random = SplitMix(seed: 0x6D65_6D6F_7279)
        let last = max(1, lengthMS - 30_000)
        return (0..<max(0, count)).map { _ in random.int(in: 0...last) }
    }

    /// What a long play and scrub broke of what memory is held to, one line
    /// each, or nothing: its peak under `ceilingMB`, and memory levelling off
    /// after the first minute, no more than `growthPercent` higher in the
    /// last whole minute than in the second (`MemoryTally.growthPercent`).
    public static func memoryProblems(_ tally: MemoryTally, ceilingMB: Double?, growthPercent: Double?) -> [String] {
        var out: [String] = []
        if let ceilingMB, tally.peakFootprintMB >= ceilingMB {
            out.append("memory peaked at \(Int(tally.peakFootprintMB.rounded())) MB, and the ceiling is "
                + "\(Int(ceilingMB.rounded())) MB")
        }
        if let allowed = growthPercent, let grew = tally.growthPercent, grew > allowed,
           let from = tally.levelMB(minute: 2), let to = tally.levelMB(minute: tally.wholeMinutes) {
            out.append(String(format: "memory kept growing: it sat at %.0f MB in minute 2 and %.0f MB in minute %d, "
                + "%.0f%% higher, and at most %.0f%% is allowed", from, to, tally.wholeMinutes, grew, allowed))
        }
        return out
    }

    /// One edit made while the document played.
    public struct EditTally: Codable, Equatable, Sendable {
        /// "trim", "move", "blade", "undo", "transition" or "title".
        public var edit: String
        /// What it did, in words ("trimmed half a second off Recording 3").
        public var did: String
        /// The edit's own work, from the call to its return.
        public var callMS: Double
        /// The longest main thread pass from the edit to a second and a half
        /// after it, playing all the while.
        public var longestPassMS: Double
        /// False when the edit found nothing to act on and was not made; nil
        /// (made) in files written before this was recorded.
        public var made: Bool?

        public init(edit: String, did: String, callMS: Double, longestPassMS: Double, made: Bool? = nil) {
            self.edit = edit
            self.did = did
            self.callMS = callMS
            self.longestPassMS = longestPassMS
            self.made = made == false ? false : nil
        }
    }

    public struct MemoryTally: Codable, Equatable, Sendable {
        /// What was going on ("playing and scrubbing the 60 minute edit").
        public var during: String
        /// One reading a second, in megabytes of footprint (what Activity
        /// Monitor shows).
        public var footprintMB: [Double]
        /// The same seconds, resident.
        public var residentMB: [Double]
        /// When each reading was taken, in seconds from the start: one a
        /// second when the main thread lets the walk look, further apart
        /// when it does not.
        public var atSeconds: [Double]?
        public var peakFootprintMB: Double
        public var peakResidentMB: Double

        public init(during: String, footprintMB: [Double], residentMB: [Double], atSeconds: [Double]? = nil) {
            self.during = during
            self.footprintMB = footprintMB
            self.residentMB = residentMB
            self.atSeconds = atSeconds
            peakFootprintMB = footprintMB.max() ?? 0
            peakResidentMB = residentMB.max() ?? 0
        }

        /// Where memory sat through minute `minute` (from 1): the median of
        /// that minute's readings, so a spike of a second or two, which comes
        /// and goes whenever a zoom or a scrub reads bigger frames, does not
        /// move it. Nil when the run did not last the whole minute.
        public func levelMB(minute: Int) -> Double? {
            guard minute >= 1 else { return nil }
            let at = atSeconds ?? footprintMB.indices.map { Double($0 + 1) }
            guard let last = at.last, last >= Double(minute * 60) - 1 else { return nil }
            let from = Double((minute - 1) * 60), to = Double(minute * 60)
            let inside = zip(at, footprintMB).filter { $0.0 > from && $0.0 <= to }.map(\.1).sorted()
            guard !inside.isEmpty else { return nil }
            let middle = inside.count / 2
            return inside.count % 2 == 1 ? inside[middle] : (inside[middle - 1] + inside[middle]) / 2
        }

        /// The last minute the run lasted the whole of.
        public var wholeMinutes: Int {
            let at = atSeconds ?? footprintMB.indices.map { Double($0 + 1) }
            return Int(((at.last ?? 0) + 1) / 60)
        }

        /// How much higher memory sits in the last whole minute than in the
        /// second, in percent. The first minute is the warm-up (the edit's
        /// first frames, fonts, the timeline's pictures) and is left out. Nil
        /// with fewer than three whole minutes, too short to say whether
        /// memory levels off.
        public var growthPercent: Double? {
            let last = wholeMinutes
            guard last >= 3, let second = levelMB(minute: 2), second > 0,
                  let end = levelMB(minute: last) else { return nil }
            return (end - second) / second * 100
        }
    }

    public struct ExportTally: Codable, Equatable, Sendable {
        /// The settings, in the sheet's words ("MP4, Standard, Full").
        public var settings: String
        public var seconds: Double
        public var megabytes: Double
        public var route: String
        /// How long the video written runs: the whole edit, or the stretch a
        /// short walk writes. Nil in a file written before it was kept.
        public var videoSeconds: Double?
        /// The longest the main thread was held while the export ran: the app
        /// stays usable while it writes, or it does not.
        public var longestMainPassMS: Double?
        /// The most memory the app had used by the time the file was
        /// written, since launch: what the export cost on top of the rest.
        /// Nil in a file written before it was kept.
        public var peakFootprintMB: Double?

        public init(settings: String, seconds: Double, megabytes: Double, route: String,
                    videoSeconds: Double? = nil, longestMainPassMS: Double? = nil) {
            self.settings = settings
            self.seconds = seconds
            self.megabytes = megabytes
            self.route = route
            self.videoSeconds = videoSeconds
            self.longestMainPassMS = longestMainPassMS
        }

        /// The time taken against the video's own length: under 1 writes it
        /// faster than it plays.
        public var timesRealTime: Double? {
            guard let videoSeconds, videoSeconds > 0 else { return nil }
            return seconds / videoSeconds
        }
    }

    /// The pictures the renderer handed the canvas while it played: how
    /// many, how long each took to draw, and how long from being asked for
    /// to arriving.
    public struct CompositeTally: Codable, Equatable, Sendable {
        public var pictures: Int
        public var drawMedianMS: Double
        public var drawWorstMS: Double
        public var askedToShownMedianMS: Double
        public var askedToShownWorstMS: Double

        public init(pictures: Int, drawMS: [Double], askedToShownMS: [Double]) {
            self.pictures = pictures
            let draw = drawMS.sorted(), asked = askedToShownMS.sorted()
            drawMedianMS = draw.isEmpty ? 0 : draw[draw.count / 2]
            drawWorstMS = draw.last ?? 0
            askedToShownMedianMS = asked.isEmpty ? 0 : asked[asked.count / 2]
            askedToShownWorstMS = asked.last ?? 0
        }
    }

    /// What the sound engine said while it played.
    public struct SoundTally: Codable, Equatable, Sendable {
        /// Pieces of sound left out because more were alive than the engine's
        /// budget: sound a person does not hear.
        public var piecesLeftOut: Int
        /// One-second looks at which the engine was not playing while the
        /// picture was.
        public var silentLooks: Int
        public var looks: Int

        public init(piecesLeftOut: Int, silentLooks: Int, looks: Int) {
            self.piecesLeftOut = piecesLeftOut
            self.silentLooks = silentLooks
            self.looks = looks
        }
    }
}

// MARK: - One run

/// Everything one run of the speed walk measured, written as `speed.json`.
public struct SpeedRun: Codable, Equatable, Sendable {
    /// How long the reference edit was, in minutes.
    public var minutes: Int?
    /// "short" (the walk set's) or "long" (the command's).
    public var form: String
    /// The commit it measured, and when.
    public var head: String
    public var date: String
    /// The Mac it ran on, in a few words.
    public var machine: String
    public var frameStepMS: Int
    public var plays: [SpeedWalk.PlayTally] = []
    public var sound: SpeedWalk.SoundTally?
    public var composites: SpeedWalk.CompositeTally?
    public var scrubs: [SpeedWalk.ScrubTally] = []
    public var edits: [SpeedWalk.EditTally] = []
    /// View bodies built per new picture with nothing being edited, by view.
    public var bodiesPerFrame: [String: Double] = [:]
    public var timeline: [SpeedWalk.FrameTimes] = []
    public var memory: SpeedWalk.MemoryTally?
    /// The most memory the app used from its launch until the walk's export
    /// (to its end, in a walk with none), counted the way Activity Monitor
    /// counts it and including spikes no reading a second would catch: the
    /// peak while the edit opens, plays, is scrubbed and edited. Every walk
    /// records it, so the short walk shows a jump on every rotating check.
    /// An export has a peak of its own (`ExportTally.peakFootprintMB`): at
    /// about twice this on 2026-11-16, it would hide a jump here. Nil in a
    /// file written before it was kept.
    public var walkPeakFootprintMB: Double?
    public var export: SpeedWalk.ExportTally?

    /// The name the walk's peak before its export is compared under.
    public static let walkPeakKey = "memory: peak playing and editing"
    /// The name an export's peak is compared under.
    public static let exportPeakKey = "export: peak memory"

    public init(minutes: Int?, form: String, head: String, date: String, machine: String, frameStepMS: Int) {
        self.minutes = minutes
        self.form = form
        self.head = head
        self.date = date
        self.machine = machine
        self.frameStepMS = frameStepMS
    }

    /// One number of a run, every one of them worse when higher.
    public struct Metric: Equatable, Sendable {
        public enum Unit: String, Sendable { case frames, ms, megabytes, seconds, bodies }
        public var key: String
        public var value: Double
        public var unit: Unit
    }

    /// Every number worth comparing, in a fixed order. A play stretch is
    /// keyed by its label, so the same seeded edit lines its cuts up.
    public var metrics: [Metric] {
        var out: [Metric] = []
        for play in plays {
            let key = play.label == "whole" ? "play" : "play \(play.label)"
            out.append(Metric(key: "\(key): dropped", value: Double(play.dropped), unit: .frames))
            out.append(Metric(key: "\(key): worst gap", value: play.worstGapMS, unit: .ms))
            if let start = play.firstPictureMS {
                out.append(Metric(key: "\(key): first picture", value: start, unit: .ms))
            }
        }
        if let sound {
            out.append(Metric(key: "sound: pieces left out", value: Double(sound.piecesLeftOut), unit: .bodies))
            out.append(Metric(key: "sound: silent looks", value: Double(sound.silentLooks), unit: .bodies))
        }
        for scrub in scrubs {
            out.append(Metric(key: "scrub \(scrub.speed): lag median", value: Double(scrub.lagMedianFrames), unit: .frames))
            out.append(Metric(key: "scrub \(scrub.speed): lag worst", value: Double(scrub.lagWorstFrames), unit: .frames))
            if let median = scrub.frameLagMedianFrames, let worst = scrub.frameLagWorstFrames {
                out.append(Metric(key: "scrub \(scrub.speed): frame lag median", value: Double(median), unit: .frames))
                out.append(Metric(key: "scrub \(scrub.speed): frame lag worst", value: Double(worst), unit: .frames))
            }
            if let median = scrub.sightLagMedianFrames, let worst = scrub.sightLagWorstFrames {
                out.append(Metric(key: "scrub \(scrub.speed): sight lag median", value: Double(median), unit: .frames))
                out.append(Metric(key: "scrub \(scrub.speed): sight lag worst", value: Double(worst), unit: .frames))
            }
            out.append(Metric(key: "scrub \(scrub.speed): time", value: scrub.seconds, unit: .seconds))
        }
        for edit in edits where edit.made != false {
            out.append(Metric(key: "edit \(edit.edit): longest pass", value: edit.longestPassMS, unit: .ms))
        }
        for (view, count) in bodiesPerFrame.sorted(by: { $0.key < $1.key }) {
            out.append(Metric(key: "bodies per frame: \(view)", value: count, unit: .bodies))
        }
        for times in timeline {
            out.append(Metric(key: "timeline \(times.label): p95", value: times.p95MS, unit: .ms))
            out.append(Metric(key: "timeline \(times.label): worst", value: times.worstMS, unit: .ms))
        }
        if let memory {
            out.append(Metric(key: "memory: peak footprint", value: memory.peakFootprintMB, unit: .megabytes))
        }
        if let walkPeakFootprintMB {
            out.append(Metric(key: Self.walkPeakKey, value: walkPeakFootprintMB, unit: .megabytes))
        }
        if let export {
            out.append(Metric(key: "export: time", value: export.seconds, unit: .seconds))
            if let pass = export.longestMainPassMS {
                out.append(Metric(key: "export: longest main pass", value: pass, unit: .ms))
            }
            if let peak = export.peakFootprintMB {
                out.append(Metric(key: Self.exportPeakKey, value: peak, unit: .megabytes))
            }
        }
        return out
    }
}

// MARK: - Several runs as one baseline

extension SpeedRun {
    /// The worst of several runs, number by number: what today's build can
    /// read on a bad run, which is what a baseline has to be when one run
    /// differs from the next by half again. Stretches, speeds and edits are
    /// matched by their names; the first run gives everything else.
    public static func envelope(of runs: [SpeedRun]) -> SpeedRun? {
        guard var out = runs.first else { return nil }
        for run in runs.dropFirst() {
            for play in run.plays {
                if let i = out.plays.firstIndex(where: { $0.label == play.label }) {
                    out.plays[i].dropped = max(out.plays[i].dropped, play.dropped)
                    out.plays[i].worstGapMS = max(out.plays[i].worstGapMS, play.worstGapMS)
                    out.plays[i].framesShown = min(out.plays[i].framesShown, play.framesShown)
                    if let start = play.firstPictureMS {
                        out.plays[i].firstPictureMS = max(out.plays[i].firstPictureMS ?? start, start)
                    }
                } else {
                    out.plays.append(play)
                }
            }
            if let sound = run.sound {
                var mine = out.sound ?? sound
                mine.piecesLeftOut = max(mine.piecesLeftOut, sound.piecesLeftOut)
                mine.silentLooks = max(mine.silentLooks, sound.silentLooks)
                out.sound = mine
            }
            for scrub in run.scrubs {
                if let i = out.scrubs.firstIndex(where: { $0.speed == scrub.speed }) {
                    out.scrubs[i].lagMedianFrames = max(out.scrubs[i].lagMedianFrames, scrub.lagMedianFrames)
                    out.scrubs[i].lagWorstFrames = max(out.scrubs[i].lagWorstFrames, scrub.lagWorstFrames)
                    if let median = scrub.frameLagMedianFrames {
                        out.scrubs[i].frameLagMedianFrames = max(out.scrubs[i].frameLagMedianFrames ?? 0, median)
                    }
                    if let worst = scrub.frameLagWorstFrames {
                        out.scrubs[i].frameLagWorstFrames = max(out.scrubs[i].frameLagWorstFrames ?? 0, worst)
                    }
                    if let median = scrub.sightLagMedianFrames {
                        out.scrubs[i].sightLagMedianFrames = max(out.scrubs[i].sightLagMedianFrames ?? 0, median)
                    }
                    if let worst = scrub.sightLagWorstFrames {
                        out.scrubs[i].sightLagWorstFrames = max(out.scrubs[i].sightLagWorstFrames ?? 0, worst)
                    }
                    out.scrubs[i].seconds = max(out.scrubs[i].seconds, scrub.seconds)
                    out.scrubs[i].worstFrameMS = max(out.scrubs[i].worstFrameMS, scrub.worstFrameMS)
                } else {
                    out.scrubs.append(scrub)
                }
            }
            for edit in run.edits {
                if let i = out.edits.firstIndex(where: { $0.edit == edit.edit }) {
                    out.edits[i].longestPassMS = max(out.edits[i].longestPassMS, edit.longestPassMS)
                    out.edits[i].callMS = max(out.edits[i].callMS, edit.callMS)
                    if edit.made != false { out.edits[i].made = nil }
                } else {
                    out.edits.append(edit)
                }
            }
            out.bodiesPerFrame.merge(run.bodiesPerFrame) { max($0, $1) }
            for times in run.timeline {
                if let i = out.timeline.firstIndex(where: { $0.label == times.label }) {
                    out.timeline[i].p95MS = max(out.timeline[i].p95MS, times.p95MS)
                    out.timeline[i].worstMS = max(out.timeline[i].worstMS, times.worstMS)
                } else {
                    out.timeline.append(times)
                }
            }
            if let memory = run.memory, memory.peakFootprintMB > (out.memory?.peakFootprintMB ?? -1) {
                out.memory = memory
            }
            if let peak = run.walkPeakFootprintMB { out.walkPeakFootprintMB = max(out.walkPeakFootprintMB ?? 0, peak) }
            let exportPeak = [out.export?.peakFootprintMB, run.export?.peakFootprintMB].compactMap { $0 }.max()
            if let export = run.export, export.seconds > (out.export?.seconds ?? -1) { out.export = export }
            if exportPeak != nil { out.export?.peakFootprintMB = exportPeak }
        }
        return out
    }
}

// MARK: - Two runs side by side

public enum SpeedCompare {

    /// How much worse than the baseline a number may read before the short
    /// walk fails, as a share of the baseline (`marginPercent`) plus a floor
    /// in the number's own unit, so a number near nothing is not failed for
    /// a frame of noise.
    public static func slack(_ unit: SpeedRun.Metric.Unit) -> Double {
        switch unit {
        case .frames: 3
        case .ms: 50
        case .megabytes: 150
        case .seconds: 2
        case .bodies: 2
        }
    }

    /// Whether a number is judged against a baseline. A transition's own
    /// worst gap is not: the whole run's worst gap already bounds it, and
    /// while stalls last seconds which cut a stall lands on is chance (8.2 s
    /// and 12.8 s at the same cut in two runs of one build, 2026-11-12).
    public static func isJudged(_ metric: SpeedRun.Metric) -> Bool {
        !(metric.key.hasPrefix("play ") && metric.key.hasSuffix(": worst gap"))
    }

    /// The numbers in `run` that read worse than `baseline` by more than the
    /// margin, one line each. A number the baseline does not have is not
    /// judged.
    public static func regressions(baseline: SpeedRun, run: SpeedRun, marginPercent: Double) -> [String] {
        let before = Dictionary(baseline.metrics.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return run.metrics.filter(isJudged).compactMap { now in
            guard let then = before[now.key] else { return nil }
            let allowed = then.value * (1 + marginPercent / 100) + slack(now.unit)
            guard now.value > allowed else { return nil }
            return "\(now.key): \(format(now.value, now.unit)) against \(format(then.value, then.unit)) "
                + "(at most \(format(allowed, now.unit)))"
        }
    }

    /// Two runs as a table: every number either has, the baseline's, the
    /// run's, and the change.
    public static func table(_ a: SpeedRun, _ b: SpeedRun, names: (String, String) = ("before", "after")) -> String {
        let left = Dictionary(a.metrics.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        let right = Dictionary(b.metrics.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        var keys = a.metrics.map(\.key)
        for key in b.metrics.map(\.key) where left[key] == nil { keys.append(key) }
        let width = max(24, (keys.map(\.count).max() ?? 0) + 2)
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        func lpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }
        var lines = [
            "\(pad("", width))\(lpad(names.0, 12))\(lpad(names.1, 12))\(lpad("change", 12))",
            "\(pad("edit", width))\(lpad(a.minutes.map { "\($0) min" } ?? "-", 12))\(lpad(b.minutes.map { "\($0) min" } ?? "-", 12))",
            "\(pad("commit", width))\(lpad(String(a.head.prefix(9)), 12))\(lpad(String(b.head.prefix(9)), 12))",
        ]
        for key in keys {
            let x = left[key], y = right[key]
            let unit = (x ?? y)?.unit ?? .ms
            let change: String
            if let x, let y {
                let delta = y.value - x.value
                change = delta == 0 ? "=" : (delta > 0 ? "+" : "") + format(delta, unit)
            } else {
                change = ""
            }
            lines.append("\(pad(key, width))\(lpad(x.map { format($0.value, unit) } ?? "-", 12))"
                + "\(lpad(y.map { format($0.value, unit) } ?? "-", 12))\(lpad(change, 12))")
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ value: Double, _ unit: SpeedRun.Metric.Unit) -> String {
        switch unit {
        case .frames: String(format: "%.0f", value)
        case .ms: String(format: "%.0fms", value)
        case .megabytes: String(format: "%.0fMB", value)
        case .seconds: String(format: "%.1fs", value)
        case .bodies: value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
        }
    }
}

// MARK: - The walk's step

/// One `speed` step of a walk (`PlaytestStep.speed`).
///
/// ```
/// {"do": "speed", "measure": "play", "fromMS": 15000, "seconds": 60}
/// {"do": "speed", "measure": "scrub", "speeds": ["slow", "medium", "fling"]}
/// {"do": "speed", "measure": "edits", "edits": ["trim", "move", "blade", "undo", "transition", "title"]}
/// {"do": "speed", "measure": "idleBuilds", "seconds": 3}
/// {"do": "speed", "measure": "timeline"}
/// {"do": "speed", "measure": "memory", "seconds": 600, "ceilingMB": 2600, "growthPercent": 10}
/// {"do": "speed", "measure": "export"}
/// {"do": "speed", "measure": "compare", "baseline": "../perf/baselines/short-6.json", "marginPercent": 50}
/// ```
///
/// `form` ("short" or "long") on any of them names the run in its file.
public struct PlaytestSpeedMeasure: Equatable, Sendable {
    public enum Measure: String, CaseIterable, Sendable {
        case play, scrub, edits, idleBuilds, timeline, memory, export, compare
    }
    public static let speeds = ["slow", "medium", "fling", "hunt"]
    public static let edits = ["trim", "move", "blade", "undo", "transition", "title"]
    /// Edits a walk may name that change what the ones after it act on, so
    /// they are never made unless named: `pick` picks the recording under
    /// the playhead and keeps it picked, as a person editing a clip has it;
    /// `unpick` picks nothing, so the next `pick` is a click on a clip with
    /// nothing picked, the one that builds the panel's sections from nothing.
    public static let namedOnlyEdits = ["pick", "unpick"]

    /// The name an edit's numbers are kept under. Made with a clip picked,
    /// an edit holds the panel's sections too and costs more, so it is a
    /// number of its own rather than one that overwrites the other; so is a
    /// pick made after `unpick` (`fromNothing`), against one that moves the
    /// pick from a clip the panel already describes.
    public static func tallyName(_ edit: String, picked: Bool, fromNothing: Bool = false) -> String {
        if edit == "pick", fromNothing { return "pick, from nothing" }
        return picked && !namedOnlyEdits.contains(edit) ? "\(edit), picked" : edit
    }

    /// Where a hand drags the playhead from and to at each speed. The three
    /// end to end speeds cross the whole edit, a fiftieth in from each end:
    /// a person travelling. A hunt crosses ten seconds from a minute in, at
    /// five times the speed it plays: a person looking for a word or a cut,
    /// which is where the frame under the hand matters most. Every end to end
    /// drag moves the playhead the better part of a second of film each
    /// refresh, so each look is a fresh seek.
    public static func scrubSpan(_ speed: String, lengthMS: Int) -> ClosedRange<Int> {
        let low = lengthMS / 50
        guard speed == "hunt" else { return low...max(low, lengthMS - lengthMS / 50) }
        let from = lengthMS >= 70_000 ? 60_000 : low
        return from...(from + 10_000)
    }

    /// How many display frames a hand takes to drag the playhead across its
    /// span at each speed: five seconds, two, and a third of one at 120 Hz;
    /// a hunt takes two.
    public static func scrubFrames(_ speed: String) -> Int {
        switch speed {
        case "slow": 600
        case "fling": 40
        default: 240
        }
    }

    public var measure: Measure?
    public var rawMeasure: String
    public var seconds: Double?
    public var fromMS: Int?
    public var speeds: [String]
    public var edits: [String]
    public var form: String?
    public var baseline: String?
    public var marginPercent: Double
    /// An export's file kept under this name in the walk's own folder, where
    /// it is otherwise thrown away: what two exports are compared by.
    public var keep: String?
    /// An export drawn the way every export was before 2026-11-16: each frame
    /// made into a picture, read back off the GPU and drawn again into the
    /// encoder's buffer. Only for comparing the pictures the two make.
    public var throughPictures: Bool
    /// A memory step's ceiling for its peak footprint, in megabytes.
    public var ceilingMB: Double?
    /// A memory step's limit on growth from minute 2 to its last whole
    /// minute, in percent (`SpeedWalk.memoryProblems`).
    public var growthPercent: Double?

    public init(measure: String, seconds: Double? = nil, fromMS: Int? = nil, speeds: [String] = [],
                edits: [String] = [], form: String? = nil, baseline: String? = nil, marginPercent: Double? = nil,
                keep: String? = nil, throughPictures: Bool = false, ceilingMB: Double? = nil,
                growthPercent: Double? = nil) {
        self.ceilingMB = ceilingMB
        self.growthPercent = growthPercent
        self.keep = keep
        self.throughPictures = throughPictures
        rawMeasure = measure
        self.measure = Measure(rawValue: measure)
        self.seconds = seconds
        self.fromMS = fromMS
        self.speeds = speeds.isEmpty ? Self.speeds : speeds
        self.edits = edits.isEmpty ? Self.edits : edits
        self.form = form
        self.baseline = baseline
        self.marginPercent = marginPercent ?? 50
    }

    /// What is wrong with the step as written, or nil.
    public var problem: (field: String, reason: String)? {
        guard let measure else {
            return ("measure", "is one of " + Measure.allCases.map(\.rawValue).joined(separator: ", "))
        }
        if let bad = speeds.first(where: { !Self.speeds.contains($0) }) {
            return ("speeds", "\(bad) is not a speed: they are slow, medium and fling")
        }
        if let bad = edits.first(where: { !Self.edits.contains($0) && !Self.namedOnlyEdits.contains($0) }) {
            return ("edits", "\(bad) is not an edit: they are " + (Self.edits + Self.namedOnlyEdits).joined(separator: ", "))
        }
        if let seconds, seconds <= 0 { return ("seconds", "must be more than nothing") }
        if let form, form != "short", form != "long" { return ("form", "is short or long") }
        if measure == .compare, baseline == nil { return ("baseline", "names the results file to compare with") }
        if marginPercent < 0 { return ("marginPercent", "cannot be less than nothing") }
        if let keep, keep.isEmpty || keep.contains("/") {
            return ("keep", "is a file name in the walk's own folder")
        }
        if measure != .memory, ceilingMB != nil || growthPercent != nil {
            return (ceilingMB != nil ? "ceilingMB" : "growthPercent", "is for a memory step")
        }
        if let ceilingMB, ceilingMB <= 0 { return ("ceilingMB", "must be more than nothing") }
        if let growthPercent, growthPercent < 0 { return ("growthPercent", "cannot be less than nothing") }
        if measure != .export, keep != nil || throughPictures {
            return (keep != nil ? "keep" : "throughPictures", "is for an export")
        }
        return nil
    }
}
