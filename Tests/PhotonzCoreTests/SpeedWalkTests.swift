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
        #expect(tally.framesDue == 61)
        #expect(tally.dropped <= 1)
        #expect(tally.worstGapMS <= 40)
        #expect(abs(tally.seconds - 2) < 0.01)
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
        #expect(tally.framesDue == 2424)
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
}
