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

        public init(label: String, seconds: Double, framesDue: Int, framesShown: Int,
                    dropped: Int, worstGapMS: Double) {
            self.label = label
            self.seconds = seconds
            self.framesDue = framesDue
            self.framesShown = framesShown
            self.dropped = dropped
            self.worstGapMS = worstGapMS
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

    /// The whole run: due by the wall clock it took, shown as every new
    /// moment after the first look, and the longest wait between two.
    public static func tally(_ samples: [PlaySample], frameStepMS: Int) -> PlayTally {
        guard let first = samples.first, let last = samples.last, frameStepMS > 0 else {
            return PlayTally(label: "whole", seconds: 0, framesDue: 0, framesShown: 0, dropped: 0, worstGapMS: 0)
        }
        let wall = max(0, last.wallMS - first.wallMS)
        let due = Int((wall / Double(frameStepMS)).rounded())
        let came = arrivals(samples)
        // The picture up at the first look was not shown BY this stretch.
        let shown = max(0, came.count - (first.shownMS == nil ? 0 : 1))
        var worst = 0.0
        var previous = first.wallMS
        for arrival in came {
            worst = max(worst, arrival.wallMS - previous)
            previous = arrival.wallMS
        }
        worst = max(worst, last.wallMS - previous)
        return PlayTally(label: "whole", seconds: wall / 1000, framesDue: due, framesShown: min(shown, due),
                         dropped: max(0, due - shown), worstGapMS: worst)
    }

    /// One transition: due as its length on the app's clock, shown as the
    /// different moments inside it that came on screen, and the longest wait
    /// between two new pictures while the playhead was crossing it, so a
    /// stall that froze the picture over a cut is charged to that cut even
    /// when no look landed inside it.
    public static func tally(_ samples: [PlaySample], over span: Span, frameStepMS: Int) -> PlayTally {
        let length = span.range.count
        let due = frameStepMS > 0 ? Int((Double(length) / Double(frameStepMS)).rounded()) : 0
        let came = arrivals(samples)
        let shown = Set(came.map(\.shownMS).filter { span.range.contains($0) }).count
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
        return PlayTally(label: span.label, seconds: Double(length) / 1000, framesDue: due,
                         framesShown: min(shown, due), dropped: max(0, due - shown), worstGapMS: worst)
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
        /// "slow", "medium" or "fling".
        public var speed: String
        /// How many display frames the drag took.
        public var frames: Int
        /// How many display frames the picture trailed the hand: the middle
        /// look and the worst.
        public var lagMedianFrames: Int
        public var lagWorstFrames: Int
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

        public init(edit: String, did: String, callMS: Double, longestPassMS: Double) {
            self.edit = edit
            self.did = did
            self.callMS = callMS
            self.longestPassMS = longestPassMS
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
        public var peakFootprintMB: Double
        public var peakResidentMB: Double

        public init(during: String, footprintMB: [Double], residentMB: [Double]) {
            self.during = during
            self.footprintMB = footprintMB
            self.residentMB = residentMB
            peakFootprintMB = footprintMB.max() ?? 0
            peakResidentMB = residentMB.max() ?? 0
        }
    }

    public struct ExportTally: Codable, Equatable, Sendable {
        /// The settings, in the sheet's words ("MP4, Standard, Full").
        public var settings: String
        public var seconds: Double
        public var megabytes: Double
        public var route: String

        public init(settings: String, seconds: Double, megabytes: Double, route: String) {
            self.settings = settings
            self.seconds = seconds
            self.megabytes = megabytes
            self.route = route
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
    public var export: SpeedWalk.ExportTally?

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
        }
        if let sound {
            out.append(Metric(key: "sound: pieces left out", value: Double(sound.piecesLeftOut), unit: .bodies))
            out.append(Metric(key: "sound: silent looks", value: Double(sound.silentLooks), unit: .bodies))
        }
        for scrub in scrubs {
            out.append(Metric(key: "scrub \(scrub.speed): lag median", value: Double(scrub.lagMedianFrames), unit: .frames))
            out.append(Metric(key: "scrub \(scrub.speed): lag worst", value: Double(scrub.lagWorstFrames), unit: .frames))
            out.append(Metric(key: "scrub \(scrub.speed): time", value: scrub.seconds, unit: .seconds))
        }
        for edit in edits {
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
        if let export {
            out.append(Metric(key: "export: time", value: export.seconds, unit: .seconds))
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
            if let export = run.export, export.seconds > (out.export?.seconds ?? -1) { out.export = export }
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
/// {"do": "speed", "measure": "memory", "seconds": 600}
/// {"do": "speed", "measure": "export"}
/// {"do": "speed", "measure": "compare", "baseline": "../perf/baselines/short-6.json", "marginPercent": 50}
/// ```
///
/// `form` ("short" or "long") on any of them names the run in its file.
public struct PlaytestSpeedMeasure: Equatable, Sendable {
    public enum Measure: String, CaseIterable, Sendable {
        case play, scrub, edits, idleBuilds, timeline, memory, export, compare
    }
    public static let speeds = ["slow", "medium", "fling"]
    public static let edits = ["trim", "move", "blade", "undo", "transition", "title"]

    /// How many display frames a hand takes to drag the playhead end to end
    /// at each speed: five seconds, two, and a third of one at 120 Hz.
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

    public init(measure: String, seconds: Double? = nil, fromMS: Int? = nil, speeds: [String] = [],
                edits: [String] = [], form: String? = nil, baseline: String? = nil, marginPercent: Double? = nil) {
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
        if let bad = edits.first(where: { !Self.edits.contains($0) }) {
            return ("edits", "\(bad) is not an edit: they are " + Self.edits.joined(separator: ", "))
        }
        if let seconds, seconds <= 0 { return ("seconds", "must be more than nothing") }
        if let form, form != "short", form != "long" { return ("form", "is short or long") }
        if measure == .compare, baseline == nil { return ("baseline", "names the results file to compare with") }
        if marginPercent < 0 { return ("marginPercent", "cannot be less than nothing") }
        return nil
    }
}
