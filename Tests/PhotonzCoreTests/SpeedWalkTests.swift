import Foundation
@testable import PhotonzCore
import Testing

/// **The speed walk's arithmetic** (`SpeedWalk.swift`, task
/// `a-speed-walk-measures-the-long-reference-edit-th`).
///
/// The probe takes looks at a playing, scrubbed and edited reference edit;
/// these are the rules that turn the looks into the numbers every later speed
/// fix is judged by, so they are pinned here rather than trusted.
@Suite("The speed walk's numbers")
struct SpeedWalkTests {

    /// A run of looks one display frame (about 8ms) apart, the picture
    /// following a 33ms clock exactly.
    static func smooth(seconds: Double) -> [SpeedWalk.PlaySample] {
        stride(from: 0.0, through: seconds * 1000, by: 8.0).map { wall in
            let ms = Int(wall)
            return SpeedWalk.PlaySample(wallMS: wall, playheadMS: ms, shownMS: ms / 33 * 33)
        }
    }

    @Test("A picture that keeps up drops nothing and never waits longer than a clock tick")
    func smoothDropsNothing() {
        let tally = SpeedWalk.tally(Self.smooth(seconds: 2), frameStepMS: 33)
        #expect(tally.framesDue == 60)
        #expect(tally.dropped == 0)
        #expect(tally.worstGapMS <= 40)
        #expect(abs(tally.seconds - 2) < 0.01)
    }

    /// Looks the way the probe really takes them (pass 18, 2026-11-19): the
    /// clock ticks about every 33ms of the wall but not on a 33ms grid, the
    /// picture is the playhead's own moment at each tick, a refresh (8.3ms)
    /// shows it, and the first new picture after Space comes about 50ms
    /// after the press.
    static func realistic(seconds: Double, startMS: Double = 50, endInFlight: Bool) -> [SpeedWalk.PlaySample] {
        var out = [SpeedWalk.PlaySample(wallMS: 0, playheadMS: 15_000, shownMS: 15_000)]
        var ticks: [Double] = []
        var tick = startMS
        var wobble = 0
        while tick < seconds * 1000 {
            ticks.append(tick)
            wobble = (wobble + 7) % 11
            tick += 29 + Double(wobble % 9)
        }
        var shown = 15_000
        var wall = 8.33
        var t = 0
        while wall < seconds * 1000 {
            var playhead = 15_000
            while t < ticks.count, ticks[t] <= wall {
                playhead = 15_000 + Int(ticks[t])
                // The picture asked at this tick is up by the next refresh,
                // except the last one when the stretch ends with it in flight.
                shown = playhead
                t += 1
            }
            if t > 0 { playhead = 15_000 + Int(ticks[t - 1]) }
            out.append(SpeedWalk.PlaySample(wallMS: wall, playheadMS: playhead, shownMS: shown))
            wall += 8.33
        }
        if endInFlight, let last = out.last {
            // The clock has ticked once more and its picture is not up yet.
            out.append(SpeedWalk.PlaySample(wallMS: last.wallMS + 1, playheadMS: last.playheadMS + 33,
                                            shownMS: last.shownMS))
        }
        return out
    }

    @Test("A picture that keeps up off the grid, starting a tick late and ending with one in flight, drops nothing")
    func realisticDropsNothing() {
        for inFlight in [false, true] {
            let tally = SpeedWalk.tally(Self.realistic(seconds: 60, endInFlight: inFlight), frameStepMS: 33)
            #expect(tally.dropped == 0, "end in flight: \(inFlight)")
            #expect(tally.framesShown == tally.framesDue)
            #expect(tally.framesDue > 1_750 && tally.framesDue < 1_900)
            // The start is its own number, not a dropped frame.
            #expect(tally.firstPictureMS.map { abs($0 - 58.3) < 9 } == true)
        }
    }

    @Test("A moment the picture jumped over is a dropped frame, wherever the clock's ticks fall")
    func skippedMomentIsDropped() {
        var samples = Self.realistic(seconds: 10, endInFlight: false)
        // Take out every look that shows one moment in the middle: the
        // picture goes straight from the moment before it to the one after.
        let moments = Array(Set(samples.compactMap(\.shownMS))).sorted()
        let gone = moments[moments.count / 2]
        let before = moments[moments.count / 2 - 1]
        samples = samples.map { sample in
            var sample = sample
            if sample.shownMS == gone { sample.shownMS = before }
            return sample
        }
        let tally = SpeedWalk.tally(samples, frameStepMS: 33)
        #expect(tally.dropped == 1)
        #expect(tally.framesShown + tally.dropped == tally.framesDue)
        // And the walk can say where it was.
        let at = SpeedWalk.droppedMoments(samples, frameStepMS: 33)
        #expect(at.count == 1)
        #expect(at.first.map { abs($0 - gone) < 10 } == true)
        // And one that skipped three in a row is three.
        let three = moments[moments.count / 3 ..< moments.count / 3 + 3]
        let held = moments[moments.count / 3 - 1]
        let worse = samples.map { sample -> SpeedWalk.PlaySample in
            var sample = sample
            if let shown = sample.shownMS, three.contains(shown) { sample.shownMS = held }
            return sample
        }
        #expect(SpeedWalk.tally(worse, frameStepMS: 33).dropped == 4)
    }

    @Test("A clock that falls behind the wall drops what it never reached, though every picture it reached was shown")
    func slowClockDrops() {
        // The playhead moves at half the wall's pace, each of its moments shown.
        let samples = stride(from: 0.0, through: 2000, by: 8).map { wall -> SpeedWalk.PlaySample in
            let ms = Int(wall / 2) / 33 * 33
            return SpeedWalk.PlaySample(wallMS: wall, playheadMS: ms, shownMS: ms)
        }
        let tally = SpeedWalk.tally(samples, frameStepMS: 33)
        #expect(tally.framesShown == 30)
        #expect(tally.dropped >= 29 && tally.dropped <= 31)
    }

    @Test("A stall is counted as dropped frames and as the gap it left")
    func stallIsDroppedAndAGap() {
        var samples = Self.smooth(seconds: 1)
        // The main thread stops for 600ms: no look at all, then the picture
        // jumps to where the clock is.
        samples.append(SpeedWalk.PlaySample(wallMS: 1600, playheadMS: 1600, shownMS: 1584))
        samples += stride(from: 1608.0, through: 2000, by: 8).map {
            SpeedWalk.PlaySample(wallMS: $0, playheadMS: Int($0), shownMS: Int($0) / 33 * 33)
        }
        let tally = SpeedWalk.tally(samples, frameStepMS: 33)
        #expect(tally.worstGapMS >= 600)
        #expect(tally.dropped >= 15)
        #expect(tally.framesShown + tally.dropped == tally.framesDue)
    }

    @Test("A picture that never changes shows nothing and waits the whole run")
    func frozenShowsNothing() {
        let samples = stride(from: 0.0, through: 1000, by: 8).map {
            SpeedWalk.PlaySample(wallMS: $0, playheadMS: Int($0), shownMS: 0)
        }
        let tally = SpeedWalk.tally(samples, frameStepMS: 33)
        #expect(tally.framesShown == 0)
        #expect(tally.dropped == tally.framesDue)
        #expect(tally.worstGapMS == 1000)
    }

    @Test("A minute with only its start and its end looked at still counts the whole minute")
    func onlyTheEnds() {
        // An hour-long edit: one tick of the clock held the main thread over
        // a minute, so the walk looked only when Space went down and when the
        // stretch ended, and the picture had not changed.
        let samples = [SpeedWalk.PlaySample(wallMS: 0, playheadMS: 15_000, shownMS: 15_000),
                       SpeedWalk.PlaySample(wallMS: 80_000, playheadMS: 38_100, shownMS: 15_000)]
        let tally = SpeedWalk.tally(samples, frameStepMS: 33)
        #expect(abs(tally.framesDue - 2424) <= 3)
        #expect(tally.framesShown == 0)
        #expect(tally.worstGapMS == 80_000)
        // A transition the playhead crossed meanwhile is charged the wait.
        let cut = SpeedWalk.tally(samples, over: SpeedWalk.Span(label: "cut", range: 16_000..<16_400), frameStepMS: 33)
        #expect(cut.worstGapMS == 80_000)
        #expect(cut.dropped == 12)
        // One the playhead never reached is not.
        let later = SpeedWalk.tally(samples, over: SpeedWalk.Span(label: "later", range: 50_000..<50_400), frameStepMS: 33)
        #expect(later.worstGapMS == 0)
    }

    @Test("A stall over a transition is charged to that transition, even with no look inside it")
    func stallChargedToTheCut() {
        var samples = Self.smooth(seconds: 1).filter { $0.wallMS < 900 }
        // Frozen from 0.9s to 1.8s; the transition runs 1.0s to 1.5s.
        samples.append(SpeedWalk.PlaySample(wallMS: 1800, playheadMS: 1800, shownMS: 1782))
        let cut = SpeedWalk.Span(label: "dissolve at 0:01.2", range: 1000..<1500)
        let tally = SpeedWalk.tally(samples, over: cut, frameStepMS: 33)
        #expect(tally.label == "dissolve at 0:01.2")
        #expect(tally.framesDue == 15)
        #expect(tally.framesShown == 0)
        #expect(tally.dropped == 15)
        #expect(tally.worstGapMS >= 900)
        // A stretch before the stall is not blamed for it.
        let early = SpeedWalk.tally(samples, over: SpeedWalk.Span(label: "early", range: 200..<500), frameStepMS: 33)
        #expect(early.worstGapMS < 50)
        #expect(early.dropped <= 1)
    }

    @Test("Every transition in the 6 minute reference edit gets its own span, labelled by kind and place")
    func referenceEditSpans() {
        let doc = ReferenceEdit.build(minutes: 6)
        let spans = SpeedWalk.transitionSpans(of: doc)
        let census = ReferenceEdit.census(of: doc)
        #expect(spans.count == census.transitions.values.reduce(0, +))
        #expect(spans.allSatisfy { !$0.range.isEmpty })
        #expect(zip(spans, spans.dropFirst()).allSatisfy { $0.range.lowerBound <= $1.range.lowerBound })
        #expect(spans.contains { $0.label.hasPrefix("push at ") })
        #expect(spans.contains { $0.label.hasPrefix("cross dissolve at ") })
        // Same seed, same labels: a cut in one run lines up with the next.
        #expect(SpeedWalk.transitionSpans(of: ReferenceEdit.build(minutes: 6)) == spans)
    }

    @Test("The clock reads minutes, seconds and a tenth")
    func clockReads() {
        #expect(SpeedWalk.clock(0) == "0:00.0")
        #expect(SpeedWalk.clock(42_050) == "0:42.0")
        #expect(SpeedWalk.clock(62_500) == "1:02.5")
    }

    @Test("A scrub's lag is the display refreshes since the hand was where the picture is")
    func scrubLags() {
        let hand = [100, 200, 300, 400, 500]
        // On time, on time, one behind, two behind, never visited.
        let shown: [Int?] = [100, 200, 200, 200, 999]
        // Each move is made at 0, 10, 20... and looked at one refresh later.
        let lags = SpeedWalk.scrubLags(hand: hand, handAtMS: [0, 10, 20, 30, 40], shown: shown,
                                       atMS: [10, 20, 30, 40, 50], refreshMS: 10)
        // On time is the next refresh; then one, two and three behind; then
        // a moment never visited, as far behind as the drag so far.
        #expect(lags == [1, 1, 2, 3, 5])
        // A look the main thread held up counts the refreshes it cost, even
        // when the picture that finally arrives is of the latest move.
        let held = SpeedWalk.scrubLags(hand: [100, 200], handAtMS: [0, 10], shown: [100, 200],
                                       atMS: [10, 510], refreshMS: 10)
        #expect(held == [1, 50])
        let stats = SpeedWalk.lagStats(lags)
        #expect(stats.median == 2)
        #expect(stats.worst == 5)
        #expect(SpeedWalk.lagStats([]) == (0, 0))
    }

    @Test("A scrub's frame lag counts a picture only once it is drawn from the frames under the hand")
    func scrubFrameLag() throws {
        // The canvas answers every move at once with the frame nearest in
        // hand, stamped with the hand's moment, so the plain lag reads one
        // refresh; the frame really under the hand lands two refreshes later.
        let hand = [100, 200, 300]
        let exact: [Int?] = [nil, 100, 200]
        let lags = SpeedWalk.scrubLags(hand: hand, handAtMS: [0, 10, 20], shown: exact,
                                       atMS: [10, 20, 30], refreshMS: 10)
        #expect(lags == [1, 2, 2])
        var tally = SpeedWalk.ScrubTally(speed: "medium", frames: 240, lagMedianFrames: 1, lagWorstFrames: 2,
                                         worstFrameMS: 9)
        tally.frameLagMedianFrames = 3
        tally.frameLagWorstFrames = 7
        var run = Self.run(dropped: 0, gap: 40, peak: 1000)
        run.scrubs = [tally]
        let keys = run.metrics.map(\.key)
        #expect(keys.contains("scrub medium: frame lag median"))
        #expect(keys.contains("scrub medium: frame lag worst"))
        // Kept worst-of in a baseline, like every other number.
        var other = run
        other.scrubs[0].frameLagWorstFrames = 9
        let both = try #require(SpeedRun.envelope(of: [run, other]))
        #expect(both.scrubs[0].frameLagWorstFrames == 9)
        #expect(both.scrubs[0].frameLagMedianFrames == 3)
        // A baseline written before the number existed still reads, and does
        // not judge it.
        let old = #"{"speed":"medium","frames":240,"lagMedianFrames":2,"lagWorstFrames":4,"worstFrameMS":20,"movesMade":241,"seconds":2}"#
        let read = try JSONDecoder().decode(SpeedWalk.ScrubTally.self, from: Data(old.utf8))
        #expect(read.frameLagMedianFrames == nil)
        var then = run
        then.scrubs = [read]
        #expect(SpeedCompare.regressions(baseline: then, run: run, marginPercent: 0).isEmpty)
    }

    @Test("A scrub's sight lag is how far, in refreshes, the hand was from the frames the picture is drawn from")
    func scrubSightLag() throws {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), old = UUID()
        // The hand needs a, then b, then c, then d (a dissolve: c and d).
        let needed: [[UUID]] = [[a], [b], [c, d], [d]]
        // Drawn: a on time; a again as a stand-in for b; b standing in for c
        // and d; then a frame from before the drag, which the hand never
        // needed, and a picture with no frames of a recording at all.
        let drawn: [Set<UUID>?] = [[a], [a], [b], [old]]
        let lags = SpeedWalk.sightLags(needed: needed, handAtMS: [0, 10, 20, 30], drawn: drawn,
                                       atMS: [10, 20, 30, 40], refreshMS: 10)
        // On time; a was under the hand two refreshes back; b one before
        // that; and a frame never under the hand is as far behind as the drag.
        #expect(lags == [1, 2, 2, 4])
        // A picture drawn from two frames is as far behind as its older one.
        let mixed = SpeedWalk.sightLags(needed: [[a], [b], [c, d]], handAtMS: [0, 10, 20],
                                        drawn: [[a], [b], [a, d]], atMS: [10, 20, 30], refreshMS: 10)
        #expect(mixed == [1, 1, 3])
        // A look with nothing drawn yet, or nothing of a recording in it,
        // judges nothing: a still part of the edit has no frame to be behind.
        // A stand-in from just ahead of the hand, read before it got there,
        // is as near as one just behind it.
        let ahead = SpeedWalk.sightLags(needed: [[a], [b], [c]], handAtMS: [0, 10, 20],
                                        drawn: [[b], [b], [b]], atMS: [10, 20, 30], refreshMS: 10)
        #expect(ahead == [0, 1, 2])
        // A recording used twice in the edit: the nearer visit counts.
        let twice = SpeedWalk.sightLags(needed: [[a], [b], [c], [a]], handAtMS: [0, 10, 20, 30],
                                        drawn: [[a], [a], [a], [a]], atMS: [10, 20, 30, 40], refreshMS: 10)
        #expect(twice == [1, 1, 0, 1])
        let still = SpeedWalk.sightLags(needed: [[], [a]], handAtMS: [0, 10], drawn: [nil, []],
                                        atMS: [10, 20], refreshMS: 10)
        #expect(still.isEmpty)
        var tally = SpeedWalk.ScrubTally(speed: "hunt", frames: 240, lagMedianFrames: 1, lagWorstFrames: 2,
                                         worstFrameMS: 9)
        tally.sightLagMedianFrames = 3
        tally.sightLagWorstFrames = 7
        var run = Self.run(dropped: 0, gap: 40, peak: 1000)
        run.scrubs = [tally]
        let keys = run.metrics.map(\.key)
        #expect(keys.contains("scrub hunt: sight lag median"))
        #expect(keys.contains("scrub hunt: sight lag worst"))
        var other = run
        other.scrubs[0].sightLagWorstFrames = 9
        let both = try #require(SpeedRun.envelope(of: [run, other]))
        #expect(both.scrubs[0].sightLagWorstFrames == 9)
        #expect(both.scrubs[0].sightLagMedianFrames == 3)
    }

    @Test("A hand's path is every grid moment it crossed, timed in proportion between its moves")
    func handPath() {
        let path = SpeedWalk.handPath(hand: [0, 100, 100, 40], handAtMS: [0, 10, 20, 30], stepMS: 33)
        #expect(path.map(\.momentMS) == [0, 33, 66, 99, 100, 100, 67, 40])
        let times = [0, 3.3, 6.6, 9.9, 10, 20, 25.5, 30]
        #expect(zip(path.map(\.atMS), times).allSatisfy { abs($0 - $1) < 0.001 })
        #expect(SpeedWalk.handPath(hand: [], handAtMS: [], stepMS: 33).isEmpty)
        #expect(SpeedWalk.handPath(hand: [5], handAtMS: [1], stepMS: 33).map(\.momentMS) == [5])
    }

    @Test("A hunting hand drags ten seconds of the edit across two, the way a person looks for a moment")
    func huntingScrub() {
        #expect(PlaytestSpeedMeasure.speeds.contains("hunt"))
        #expect(PlaytestSpeedMeasure.scrubFrames("hunt") == 240)
        // The end to end speeds cross the whole edit, a fiftieth in from each end.
        #expect(PlaytestSpeedMeasure.scrubSpan("medium", lengthMS: 360_000) == 7_200...352_800)
        // A hunt crosses ten seconds from a minute in, or what there is of it.
        #expect(PlaytestSpeedMeasure.scrubSpan("hunt", lengthMS: 360_000) == 60_000...70_000)
        #expect(PlaytestSpeedMeasure.scrubSpan("hunt", lengthMS: 30_000) == 600...10_600)
    }

    @Test("Frame times read the gaps between refreshes against the display's interval")
    func frameTimesRead() {
        var at: [Double] = stride(from: 0.0, through: 800, by: 8.33).map { $0 }
        at.append(at.last! + 50)
        let times = SpeedWalk.frameTimes("scroll", refreshesAtMS: at, refreshMS: 8.33)
        #expect(times.frames == at.count - 1)
        #expect(abs(times.medianMS - 8.33) < 0.01)
        #expect(abs(times.worstMS - 50) < 0.01)
        #expect(times.late == 1)
    }

    static func run(dropped: Int, gap: Double, peak: Double) -> SpeedRun {
        var run = SpeedRun(minutes: 6, form: "short", head: "abc", date: "2026-11-12", machine: "test", frameStepMS: 33)
        run.plays = [SpeedWalk.PlayTally(label: "whole", seconds: 60, framesDue: 1800, framesShown: 1800 - dropped,
                                         dropped: dropped, worstGapMS: gap)]
        run.memory = SpeedWalk.MemoryTally(during: "test", footprintMB: [peak / 2, peak], residentMB: [peak])
        return run
    }

    @Test("A run worse than its baseline by more than the margin is named, number by number")
    func regressionsNamed() {
        let base = Self.run(dropped: 100, gap: 400, peak: 1000)
        #expect(SpeedCompare.regressions(baseline: base, run: base, marginPercent: 50).isEmpty)
        // Inside the margin: 140 against 100 at 50% plus 3 frames.
        #expect(SpeedCompare.regressions(baseline: base, run: Self.run(dropped: 140, gap: 600, peak: 1500),
                                         marginPercent: 50).isEmpty)
        let worse = SpeedCompare.regressions(baseline: base, run: Self.run(dropped: 200, gap: 400, peak: 1000),
                                             marginPercent: 50)
        #expect(worse.count == 1)
        #expect(worse.first?.hasPrefix("play: dropped") == true)
        // Better is never a regression.
        #expect(SpeedCompare.regressions(baseline: base, run: Self.run(dropped: 0, gap: 0, peak: 10),
                                         marginPercent: 0).isEmpty)
    }

    @Test("A transition's own worst gap is shown but not judged; the whole run's gap bounds it")
    func cutGapsNotJudged() {
        var base = Self.run(dropped: 100, gap: 400, peak: 1000)
        base.plays.append(SpeedWalk.PlayTally(label: "cube at 0:59.8", seconds: 0.4, framesDue: 12, framesShown: 0,
                                              dropped: 12, worstGapMS: 400))
        var run = base
        run.plays[1].worstGapMS = 4000
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).isEmpty)
        run.plays[0].worstGapMS = 4000
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).count == 1)
        #expect(SpeedCompare.table(base, run).contains("play cube at 0:59.8: worst gap"))
    }

    @Test("An end to end drag's exact-frame lags are shown but not judged; its lag and a hunt's are")
    func endToEndFrameLagsNotJudged() {
        func scrub(_ speed: String, frameMedian: Int, frameWorst: Int, sightMedian: Int, sightWorst: Int,
                   lagMedian: Int = 1, lagWorst: Int = 3) -> SpeedWalk.ScrubTally {
            var tally = SpeedWalk.ScrubTally(speed: speed, frames: 240, lagMedianFrames: lagMedian,
                                             lagWorstFrames: lagWorst, worstFrameMS: 20)
            tally.frameLagMedianFrames = frameMedian
            tally.frameLagWorstFrames = frameWorst
            tally.sightLagMedianFrames = sightMedian
            tally.sightLagWorstFrames = sightWorst
            return tally
        }
        var base = Self.run(dropped: 0, gap: 40, peak: 1000)
        base.scrubs = [scrub("medium", frameMedian: 40, frameWorst: 152, sightMedian: 1, sightWorst: 91),
                       scrub("fling", frameMedian: 60, frameWorst: 200, sightMedian: 1, sightWorst: 120),
                       scrub("hunt", frameMedian: 1, frameWorst: 8, sightMedian: 1, sightWorst: 6)]
        // What 45 runs of unchanged code read on 2026-11-18 to 11-22: medium's
        // frame under the hand 17 to 81 refreshes at the median, its sight
        // worst 33 to 159. Not a regression.
        var noisy = base
        noisy.scrubs[0] = scrub("medium", frameMedian: 81, frameWorst: 320, sightMedian: 1, sightWorst: 159)
        noisy.scrubs[1] = scrub("fling", frameMedian: 150, frameWorst: 500, sightMedian: 1, sightWorst: 300)
        #expect(SpeedCompare.regressions(baseline: base, run: noisy, marginPercent: 50).isEmpty)
        // Still written down, side by side.
        #expect(SpeedCompare.table(base, noisy).contains("scrub medium: frame lag median"))
        // The picture falling behind the hand at medium is still judged...
        var behind = base
        behind.scrubs[0] = scrub("medium", frameMedian: 40, frameWorst: 152, sightMedian: 9, sightWorst: 91,
                                 lagMedian: 9, lagWorst: 30)
        let named = SpeedCompare.regressions(baseline: base, run: behind, marginPercent: 50)
        #expect(named.contains { $0.hasPrefix("scrub medium: lag median") })
        #expect(named.contains { $0.hasPrefix("scrub medium: lag worst") })
        #expect(named.contains { $0.hasPrefix("scrub medium: sight lag median") })
        // ...and so is every number of a hunt, where the frame under the hand is the point.
        var slowHunt = base
        slowHunt.scrubs[2] = scrub("hunt", frameMedian: 9, frameWorst: 40, sightMedian: 9, sightWorst: 40)
        #expect(SpeedCompare.regressions(baseline: base, run: slowHunt, marginPercent: 50).count == 4)
    }

    @Test("A baseline from several runs is the worst of them, number by number")
    func envelopeIsTheWorst() throws {
        var a = Self.run(dropped: 100, gap: 900, peak: 1000)
        a.edits = [SpeedWalk.EditTally(edit: "blade", did: "", callMS: 300, longestPassMS: 1200)]
        var b = Self.run(dropped: 140, gap: 400, peak: 1200)
        b.edits = [SpeedWalk.EditTally(edit: "blade", did: "", callMS: 200, longestPassMS: 1500),
                   SpeedWalk.EditTally(edit: "undo", did: "", callMS: 60, longestPassMS: 3000)]
        let both = try #require(SpeedRun.envelope(of: [a, b]))
        #expect(both.plays[0].dropped == 140)
        #expect(both.plays[0].worstGapMS == 900)
        #expect(both.memory?.peakFootprintMB == 1200)
        #expect(both.edits.first { $0.edit == "blade" }?.longestPassMS == 1500)
        #expect(both.edits.first { $0.edit == "undo" }?.longestPassMS == 3000)
        // Each run is within the envelope at no margin at all.
        #expect(SpeedCompare.regressions(baseline: both, run: a, marginPercent: 0).isEmpty)
        #expect(SpeedCompare.regressions(baseline: both, run: b, marginPercent: 0).isEmpty)
        #expect(SpeedRun.envelope(of: []) == nil)
    }

    @Test("An edit that found nothing to act on is written down but never judged")
    func unmadeEditNotJudged() {
        var base = Self.run(dropped: 100, gap: 400, peak: 1000)
        base.edits = [SpeedWalk.EditTally(edit: "blade", did: "not made: nothing to cut", callMS: 0,
                                          longestPassMS: 0, made: false)]
        var run = base
        run.edits = [SpeedWalk.EditTally(edit: "blade", did: "cut", callMS: 300, longestPassMS: 9000)]
        #expect(!base.metrics.contains { $0.key == "edit blade: longest pass" })
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 0).isEmpty)
        #expect(run.edits[0].made == nil)
    }

    @Test("A number near nothing is not failed for a frame of noise")
    func slackFloor() {
        let base = Self.run(dropped: 0, gap: 10, peak: 100)
        #expect(SpeedCompare.regressions(baseline: base, run: Self.run(dropped: 3, gap: 55, peak: 240),
                                         marginPercent: 0).isEmpty)
    }

    @Test("Two runs print side by side with the change, and a run reads back from its file")
    func tableAndFile() throws {
        let a = Self.run(dropped: 100, gap: 400, peak: 1000)
        var b = Self.run(dropped: 40, gap: 120, peak: 900)
        b.export = SpeedWalk.ExportTally(settings: "MP4, Standard, Full", seconds: 90, megabytes: 300, route: "composite")
        let table = SpeedCompare.table(a, b)
        #expect(table.contains("play: dropped"))
        #expect(table.contains("-60"))
        #expect(table.contains("export: time"))
        let data = try JSONEncoder().encode(b)
        #expect(try JSONDecoder().decode(SpeedRun.self, from: data) == b)
    }

    @Test("An export says how long the video it wrote runs, how many times real time that is, and its longest main thread pass")
    func exportPaceAndMainThread() throws {
        var run = Self.run(dropped: 0, gap: 10, peak: 100)
        run.export = SpeedWalk.ExportTally(settings: "MP4, Standard, Full", seconds: 30, megabytes: 40,
                                           route: "drawn", videoSeconds: 60, longestMainPassMS: 22)
        #expect(run.export?.timesRealTime == 0.5)
        let keys = run.metrics.map(\.key)
        #expect(keys.contains("export: time"))
        #expect(keys.contains("export: longest main pass"))
        // A slower export, or one that holds the main thread, is named.
        var slower = run
        slower.export?.seconds = 60
        slower.export?.longestMainPassMS = 400
        let worse = SpeedCompare.regressions(baseline: run, run: slower, marginPercent: 50)
        #expect(worse.contains { $0.contains("export: time") })
        #expect(worse.contains { $0.contains("export: longest main pass") })
    }

    @Test("A results file written before an export said its length still reads back")
    func oldExportReadsBack() throws {
        let json = #"{"settings": "MP4, Standard, Full", "seconds": 1984, "megabytes": 668.7, "route": "drawn"}"#
        let tally = try JSONDecoder().decode(SpeedWalk.ExportTally.self, from: Data(json.utf8))
        #expect(tally.seconds == 1984)
        #expect(tally.videoSeconds == nil && tally.longestMainPassMS == nil && tally.timesRealTime == nil)
    }
}

@Suite("The speed walk's step")
struct SpeedWalkStepTests {

    @Test("A speed step reads from a walk, and a wrong one says which field is wrong")
    func parses() throws {
        let json = """
        {"steps": [
          {"do": "speed", "measure": "play", "fromMS": 15000, "seconds": 60, "form": "short"},
          {"do": "speed", "measure": "scrub", "speeds": ["medium"]},
          {"do": "speed", "measure": "edits"},
          {"do": "speed", "measure": "compare", "baseline": "base.json", "marginPercent": 40}
        ]}
        """
        let script = try PlaytestScript.decode(Data(json.utf8))
        #expect(script.steps.count == 4)
        guard case .speed(let play) = script.steps[0], case .speed(let scrub) = script.steps[1],
              case .speed(let edits) = script.steps[2], case .speed(let compare) = script.steps[3] else {
            Issue.record("not speed steps")
            return
        }
        #expect(play.measure == .play && play.fromMS == 15000 && play.seconds == 60 && play.form == "short")
        #expect(scrub.speeds == ["medium"])
        #expect(edits.edits == PlaytestSpeedMeasure.edits)
        #expect(compare.baseline == "base.json" && compare.marginPercent == 40)
        #expect(PlaytestStep.names.contains("speed"))
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("speed"))
        for bad in [#"{"do": "speed", "measure": "dance"}"#, #"{"do": "speed", "measure": "scrub", "speeds": ["warp"]}"#,
                    #"{"do": "speed", "measure": "compare"}"#] {
            #expect(throws: PlaytestScriptError.self) { try PlaytestScript.decode(Data("{\"steps\": [\(bad)]}".utf8)) }
        }
    }

    @Test("An export step can time a stretch, keep its file, and draw the way exports did before they drew on the GPU")
    func exportOptions() throws {
        let json = """
        {"steps": [
          {"do": "speed", "measure": "export", "fromMS": 50000, "seconds": 30, "keep": "after.mp4"},
          {"do": "speed", "measure": "export", "keep": "before.mp4", "throughPictures": true},
          {"do": "speed", "measure": "export"}
        ]}
        """
        let script = try PlaytestScript.decode(Data(json.utf8))
        guard case .speed(let stretch) = script.steps[0], case .speed(let before) = script.steps[1],
              case .speed(let plain) = script.steps[2] else {
            Issue.record("not speed steps")
            return
        }
        #expect(stretch.fromMS == 50000 && stretch.seconds == 30 && stretch.keep == "after.mp4" && !stretch.throughPictures)
        #expect(before.keep == "before.mp4" && before.throughPictures)
        #expect(plain.keep == nil && !plain.throughPictures)
        for bad in [#"{"do": "speed", "measure": "export", "keep": "../out.mp4"}"#,
                    #"{"do": "speed", "measure": "play", "throughPictures": true}"#] {
            #expect(throws: PlaytestScriptError.self) { try PlaytestScript.decode(Data("{\"steps\": [\(bad)]}".utf8)) }
        }
    }

    @Test("A pick is an edit a walk may name, never one it makes unasked, and what follows it is counted apart")
    func aPickIsNamedNotAssumed() throws {
        let json = #"{"steps": [{"do": "speed", "measure": "edits", "edits": ["trim", "pick", "trim", "blade", "undo"]}]}"#
        let script = try PlaytestScript.decode(Data(json.utf8))
        guard case .speed(let step) = script.steps.first else {
            Issue.record("not a speed step")
            return
        }
        #expect(step.problem == nil)
        #expect(step.edits == ["trim", "pick", "trim", "blade", "undo"])
        // An edits step that names none makes the same six it always has:
        // a pick changes what every edit after it acts on.
        #expect(!PlaytestSpeedMeasure.edits.contains("pick"))
        // The same edit with a clip held is a number of its own, so a
        // baseline holds both and neither overwrites the other.
        #expect(PlaytestSpeedMeasure.tallyName("trim", picked: false) == "trim")
        #expect(PlaytestSpeedMeasure.tallyName("trim", picked: true) == "trim, picked")
        #expect(PlaytestSpeedMeasure.tallyName("pick", picked: true) == "pick")
    }

    @Test("Unpick lets a walk time a click on a clip when nothing is picked, under a name of its own")
    func unpickTimesAPickFromNothing() throws {
        let json = #"{"steps": [{"do": "speed", "measure": "edits", "edits": ["pick", "unpick", "pick", "trim"]}]}"#
        let script = try PlaytestScript.decode(Data(json.utf8))
        guard case .speed(let step) = script.steps.first else {
            Issue.record("not a speed step")
            return
        }
        #expect(step.problem == nil)
        // Never made unasked: it changes what every edit after it acts on.
        #expect(!PlaytestSpeedMeasure.edits.contains("unpick"))
        #expect(PlaytestSpeedMeasure.tallyName("unpick", picked: true) == "unpick")
        // The pick after it builds the panel's sections from nothing, which
        // costs far more than moving a pick between clips, so it is a number
        // of its own and never overwrites the other.
        #expect(PlaytestSpeedMeasure.tallyName("pick", picked: false, fromNothing: true) == "pick, from nothing")
        #expect(PlaytestSpeedMeasure.tallyName("pick", picked: false, fromNothing: false) == "pick")
        #expect(PlaytestSpeedMeasure.tallyName("trim", picked: false, fromNothing: true) == "trim")
    }

    @Test("Nothing is timed like an edit, so a walk says what the main thread does while it plays with no edit at all")
    func nothingIsTheControl() throws {
        let json = #"{"steps": [{"do": "speed", "measure": "edits", "edits": ["nothing", "pick", "nothing", "trim"]}]}"#
        let script = try PlaytestScript.decode(Data(json.utf8))
        guard case .speed(let step) = script.steps.first else {
            Issue.record("not a speed step")
            return
        }
        #expect(step.problem == nil)
        // Never made unasked: an edits step that names none makes the six
        // real edits, as it always has.
        #expect(!PlaytestSpeedMeasure.edits.contains("nothing"))
        #expect(PlaytestSpeedMeasure.controls == ["nothing"])
        // With a clip picked the panel's sections are on screen and every
        // pass costs more, so the floor beside a picked edit is its own number.
        #expect(PlaytestSpeedMeasure.tallyName("nothing", picked: false) == "nothing")
        #expect(PlaytestSpeedMeasure.tallyName("nothing", picked: true) == "nothing, picked")
        // A name that is none of them is still refused, and the refusal lists the control.
        let bad = PlaytestSpeedMeasure(measure: "edits", edits: ["nap"])
        #expect(bad.problem?.field == "edits")
        #expect(bad.problem?.reason.contains("nothing") == true)
    }

    @Test("An edit tallied twice keeps its worse number, so a lucky repeat never hides a slow one")
    func aRepeatedTallyKeepsTheWorse() {
        var tallies: [SpeedWalk.EditTally] = []
        SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: "undo, picked", did: "a", callMS: 1, longestPassMS: 22), in: &tallies)
        SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: "undo, picked", did: "b", callMS: 1, longestPassMS: 16), in: &tallies)
        SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: "trim", did: "c", callMS: 1, longestPassMS: 13), in: &tallies)
        #expect(tallies.map(\.edit) == ["undo, picked", "trim"])
        #expect(tallies.first?.longestPassMS == 22)
        SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: "trim", did: "d", callMS: 1, longestPassMS: 19), in: &tallies)
        #expect(tallies.last?.did == "d")
        // One not made never replaces one that was.
        SpeedWalk.EditTally.keepWorse(SpeedWalk.EditTally(edit: "trim", did: "e", callMS: 0, longestPassMS: 0, made: false), in: &tallies)
        #expect(tallies.last?.did == "d")
    }
}

@Suite("Memory over a long play and scrub")
struct SpeedWalkMemoryTests {

    /// Ten minutes of readings, one a second: `level(minute)` each second,
    /// with a spike of `spike` MB every half minute.
    static func tally(minutes: Int = 10, spike: Double = 0, level: (Int) -> Double) -> SpeedWalk.MemoryTally {
        var footprint: [Double] = []
        var at: [Double] = []
        for second in 1...(minutes * 60) {
            let minute = (second - 1) / 60 + 1
            footprint.append(level(minute) + (second % 30 == 0 ? spike : 0))
            at.append(Double(second))
        }
        return SpeedWalk.MemoryTally(during: "test", footprintMB: footprint, residentMB: footprint, atSeconds: at)
    }

    @Test("A minute's level is where memory sits most of it, so a spike of a second or two does not move it")
    func levelIgnoresSpikes() {
        let flat = Self.tally(spike: 1500) { _ in 1200 }
        #expect(flat.levelMB(minute: 2) == 1200)
        #expect(flat.levelMB(minute: 10) == 1200)
        #expect(flat.levelMB(minute: 11) == nil)
        #expect(flat.peakFootprintMB == 2700)
        #expect(flat.growthPercent == 0)
    }

    @Test("Growth is from minute 2 to the last whole minute, the first minute being the warm-up")
    func growthFromMinuteTwo() throws {
        let climbing = Self.tally { minute in minute == 1 ? 600 : 1000 + Double(minute - 2) * 25 }
        // Minute 2 sits at 1000, minute 10 at 1200: 20 percent.
        #expect(abs(try #require(climbing.growthPercent) - 20) < 0.01)
        // Two whole minutes say nothing about levelling off.
        #expect(Self.tally(minutes: 2) { _ in 1000 }.growthPercent == nil)
        // Readings with no times (a file written before they were kept) are one a second.
        let untimed = SpeedWalk.MemoryTally(during: "test", footprintMB: climbing.footprintMB,
                                            residentMB: climbing.residentMB)
        #expect(untimed.levelMB(minute: 10) == climbing.levelMB(minute: 10))
    }

    @Test("A memory run is held to a ceiling for its peak and to levelling off after the first minute")
    func verdict() {
        let calm = Self.tally(spike: 800) { _ in 1200 }
        #expect(SpeedWalk.memoryProblems(calm, ceilingMB: 2500, growthPercent: 10).isEmpty)
        let tall = SpeedWalk.memoryProblems(calm, ceilingMB: 1800, growthPercent: 10)
        #expect(tall.count == 1)
        #expect(tall.first?.contains("2000 MB") == true)
        #expect(tall.first?.contains("1800 MB") == true)
        let climbing = Self.tally { minute in 1000 + Double(minute) * 40 }
        let grows = SpeedWalk.memoryProblems(climbing, ceilingMB: nil, growthPercent: 10)
        #expect(grows.count == 1)
        #expect(grows.first?.contains("minute 2") == true)
        // Too short a run to say whether it levels off is never failed for it.
        #expect(SpeedWalk.memoryProblems(Self.tally(minutes: 2) { $0 == 1 ? 100 : 5000 },
                                         ceilingMB: nil, growthPercent: 10).isEmpty)
    }

    @Test("The whole walk's peak is a number of its own, judged against the baseline and kept worst-of in an envelope")
    func walkPeak() throws {
        var base = SpeedRun(minutes: 6, form: "short", head: "a", date: "2026-11-16", machine: "test", frameStepMS: 33)
        #expect(!base.metrics.contains { $0.key == SpeedRun.walkPeakKey })
        base.walkPeakFootprintMB = 1000
        #expect(base.metrics.contains { $0.key == SpeedRun.walkPeakKey && $0.value == 1000 && $0.unit == .megabytes })
        var run = base
        run.walkPeakFootprintMB = 1700
        let worse = SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50)
        #expect(worse.count == 1)
        #expect(worse.first?.hasPrefix(SpeedRun.walkPeakKey) == true)
        run.walkPeakFootprintMB = 1600
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).isEmpty)
        let both = try #require(SpeedRun.envelope(of: [base, run]))
        #expect(both.walkPeakFootprintMB == 1600)
        let data = try JSONEncoder().encode(run)
        #expect(try JSONDecoder().decode(SpeedRun.self, from: data).walkPeakFootprintMB == 1600)
    }

    @Test("A play's longest main thread pass is a number of its own, judged only once a baseline has it")
    func playLongestPass() throws {
        var base = SpeedRun(minutes: 6, form: "short", head: "a", date: "2026-11-22", machine: "test", frameStepMS: 33)
        base.plays = [SpeedWalk.PlayTally(label: "whole", seconds: 60, framesDue: 1818, framesShown: 1818,
                                          dropped: 0, worstGapMS: 60)]
        // A baseline from before the number was kept says nothing about it.
        #expect(!base.metrics.contains { $0.key == SpeedRun.playLongestPassKey })
        var run = base
        run.plays[0].longestPassMS = 40
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).isEmpty)
        base.plays[0].longestPassMS = 8
        #expect(base.metrics.contains { $0.key == SpeedRun.playLongestPassKey && $0.value == 8 && $0.unit == .ms })
        // The panel building its sections afresh as a clip went by read 25 ms.
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50)
            .first?.hasPrefix(SpeedRun.playLongestPassKey) == true)
        run.plays[0].longestPassMS = 9
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).isEmpty)
        let both = try #require(SpeedRun.envelope(of: [base, run]))
        #expect(both.plays[0].longestPassMS == 9)
        let data = try JSONEncoder().encode(run)
        #expect(try JSONDecoder().decode(SpeedRun.self, from: data).plays[0].longestPassMS == 9)
    }

    @Test("An export's peak memory is a number of its own, so an export's cost never hides a jump while playing")
    func exportPeak() throws {
        var base = SpeedRun(minutes: 6, form: "short", head: "a", date: "2026-11-16", machine: "test", frameStepMS: 33)
        base.walkPeakFootprintMB = 1700
        base.export = SpeedWalk.ExportTally(settings: "MP4, Standard, Full", seconds: 14, megabytes: 54, route: "drawn")
        #expect(!base.metrics.contains { $0.key == SpeedRun.exportPeakKey })
        base.export?.peakFootprintMB = 3900
        #expect(base.metrics.contains { $0.key == SpeedRun.exportPeakKey && $0.value == 3900 })
        var run = base
        run.walkPeakFootprintMB = 2900
        let worse = SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50)
        #expect(worse.count == 1 && worse.first?.hasPrefix(SpeedRun.walkPeakKey) == true)
        run = base
        run.export?.peakFootprintMB = 6500
        #expect(SpeedCompare.regressions(baseline: base, run: run, marginPercent: 50).first?.hasPrefix(SpeedRun.exportPeakKey) == true)
        // The worst of several runs keeps the highest export peak, whichever run took longest.
        var quick = base
        quick.export?.seconds = 10
        quick.export?.peakFootprintMB = 4200
        let both = try #require(SpeedRun.envelope(of: [base, quick]))
        #expect(both.export?.seconds == 14 && both.export?.peakFootprintMB == 4200)
    }

    @Test("A memory step carries its ceiling and its growth limit; other steps may not")
    func stepFields() throws {
        let json = #"{"steps": [{"do": "speed", "measure": "memory", "seconds": 600, "ceilingMB": 2600, "growthPercent": 10}]}"#
        let script = try PlaytestScript.decode(Data(json.utf8))
        guard case .speed(let memory) = script.steps[0] else {
            Issue.record("not a speed step")
            return
        }
        #expect(memory.ceilingMB == 2600 && memory.growthPercent == 10)
        for bad in [#"{"do": "speed", "measure": "play", "ceilingMB": 2000}"#,
                    #"{"do": "speed", "measure": "memory", "growthPercent": -1}"#,
                    #"{"do": "speed", "measure": "memory", "ceilingMB": 0}"#] {
            #expect(throws: PlaytestScriptError.self) { try PlaytestScript.decode(Data("{\"steps\": [\(bad)]}".utf8)) }
        }
    }
}

@Suite("Where the memory walk's hand takes the playhead")
struct SpeedWalkScrubPlacesTests {

    @Test("The same places every run, so two runs of the memory walk play and scrub the same parts of the edit")
    func samePlacesEveryRun() {
        let length = 3_600_000
        let a = SpeedWalk.memoryScrubPlaces(count: 20, lengthMS: length)
        #expect(a == SpeedWalk.memoryScrubPlaces(count: 20, lengthMS: length))
        #expect(a.count == 20)
        #expect(a.allSatisfy { (0...(length - 30_000)).contains($0) })
        // Spread over the edit, not bunched at one end.
        #expect(Set(a.map { $0 * 4 / length }).count >= 3)
        #expect(SpeedWalk.memoryScrubPlaces(count: 3, lengthMS: 10_000).allSatisfy { (0...1).contains($0) })
    }
}

@Suite("How far the sound comes out from the picture on screen")
struct SpeedWalkSoundSyncTests {

    @Test("Median, latest and earliest of the looks, in milliseconds the sound is behind the picture")
    func spread() {
        let tally = SpeedWalk.SyncTally(soundBehindMS: [190, 180, 185, 175, 200], outputLatencyMS: 12)
        #expect(tally.looks == 5)
        #expect(tally.medianBehindMS == 185)
        #expect(tally.latestBehindMS == 200)
        #expect(tally.earliestBehindMS == 175)
        #expect(tally.outputLatencyMS == 12)
    }

    @Test("In step means no look is more than 45ms early or 125ms late (ITU-R BT.1359), and the tight reading is 45 either way")
    func limits() {
        #expect(SpeedWalk.SyncTally(soundBehindMS: [10, 124, -20], outputLatencyMS: 0).inStep)
        #expect(SpeedWalk.SyncTally(soundBehindMS: [10, -44], outputLatencyMS: 0).inStep)
        #expect(!SpeedWalk.SyncTally(soundBehindMS: [10, 126], outputLatencyMS: 0).inStep)
        #expect(!SpeedWalk.SyncTally(soundBehindMS: [10, -46], outputLatencyMS: 0).inStep)
        #expect(SpeedWalk.SyncTally(soundBehindMS: [44, -44], outputLatencyMS: 0).withinTightLimit)
        #expect(!SpeedWalk.SyncTally(soundBehindMS: [46, 0], outputLatencyMS: 0).withinTightLimit)
        // No looks is no answer, never a pass.
        #expect(!SpeedWalk.SyncTally(soundBehindMS: [], outputLatencyMS: 0).inStep)
    }

    @Test("A frame is on screen for its whole step, so the sound is set against the middle of it")
    func frameMiddle() {
        // Heard exactly at the middle of a 33ms frame stamped 1000: in step.
        #expect(SpeedWalk.SyncTally.soundBehindMS(shownMS: 1000, heardMS: 1016.5, frameStepMS: 33) == 0)
        // Heard at the frame's own stamp: the sound is half a frame behind.
        #expect(SpeedWalk.SyncTally.soundBehindMS(shownMS: 1000, heardMS: 1000, frameStepMS: 33) == 16.5)
    }

    @Test("A run written before the sync was kept still reads")
    func oldRunsRead() throws {
        let old = #"{"piecesLeftOut": 0, "silentLooks": 0, "looks": 3}"#
        let sound = try JSONDecoder().decode(SpeedWalk.SoundTally.self, from: Data(old.utf8))
        #expect(sound.sync == nil)
    }
}
