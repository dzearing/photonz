import Foundation
import PhotonzCore
import Testing

/// A walk judges a click by the longest pass of main thread work after it: a
/// pass longer than a frame is a frame the app did not draw.
///
/// The meter used to end a pass when a run of the run loop ended and start
/// the next one when a run began, and AppKit hands every queued event out
/// BETWEEN two runs. So the time in between counted for nothing: a click's
/// release, and the 14 history tiles it built, landed there, and a filter
/// switch that held the thread for 58ms read 5.6ms (measured 2026-10-03,
/// history-filter-switch-speed-walk). The time between runs is a pass of its
/// own now. The run edges still cut, because a frame is committed inside a
/// run: joining everything from wake to sleep into one pass would count two
/// stretches with a frame drawn between them as one frame missed.
@Suite("How the main thread's time is cut into passes")
struct MainThreadPassClockTests {

    private func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 } == true }

    @Test("An event handled between two runs of the run loop is a pass of its own")
    func eventBetweenRunsIsCounted() {
        var clock = MainThreadPassClock()
        #expect(clock.record(.woke, at: 0) == nil)
        #expect(close(clock.record(.leftARun, at: 0.006), 0.006))
        // AppKit sends the release here, outside any run.
        #expect(close(clock.record(.enteredARun, at: 0.064), 0.058))
        #expect(close(clock.record(.fallingAsleep, at: 0.070), 0.006))
    }

    @Test("A run inside a run cuts the pass too")
    func nestedRunsCut() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        #expect(close(clock.record(.enteredARun, at: 0.010), 0.010))
        #expect(close(clock.record(.leftARun, at: 0.011), 0.001))
        #expect(close(clock.record(.fallingAsleep, at: 0.020), 0.009))
    }

    @Test("Asleep is not busy: each wake to sleep is its own pass")
    func sleepIsNotCounted() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        let first = clock.record(.fallingAsleep, at: 0.005)
        _ = clock.record(.woke, at: 0.100)
        let second = clock.record(.fallingAsleep, at: 0.103)
        #expect(first.map { abs($0 - 0.005) < 1e-9 } == true)
        #expect(second.map { abs($0 - 0.003) < 1e-9 } == true)
        #expect(clock.record(.fallingAsleep, at: 0.2) == nil)
    }

    @Test("A thread seen entering or leaving a run is awake, even with no pass open")
    func runEdgesOpenAPass() {
        var clock = MainThreadPassClock()
        #expect(clock.record(.leftARun, at: 1.0) == nil)
        #expect(close(clock.record(.fallingAsleep, at: 1.010), 0.010))
    }

    @Test("A pass is closed at a run edge with the harness's time off it, and the next starts clean")
    func harnessTimeStaysInItsPass() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        _ = clock.exclude(0.004)
        #expect(close(clock.record(.leftARun, at: 0.010), 0.006))
        #expect(close(clock.record(.enteredARun, at: 0.020), 0.010))
    }

    @Test("The harness's own time comes off the pass it happened in")
    func harnessTimeInAPass() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        #expect(clock.exclude(0.004) == 0)
        let pass = clock.record(.fallingAsleep, at: 0.010)
        #expect(pass.map { abs($0 - 0.006) < 1e-9 } == true)
    }

    @Test("Harness time with no pass open is handed back to come off the totals")
    func harnessTimeOutsideAPass() {
        var clock = MainThreadPassClock()
        #expect(clock.exclude(0.004) == 0.004)
    }

    @Test("Zeroed part way through a pass, it counts from the zeroing")
    func zeroedMidPass() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        _ = clock.exclude(0.002)
        clock.restart(at: 0.050)
        #expect(clock.running(at: 0.055).map { abs($0 - 0.005) < 1e-9 } == true)
        let pass = clock.record(.fallingAsleep, at: 0.060)
        #expect(pass.map { abs($0 - 0.010) < 1e-9 } == true)
        #expect(clock.running(at: 0.07) == nil)
    }

    @Test("A pass dropped on purpose leaves nothing open")
    func dropped() {
        var clock = MainThreadPassClock()
        _ = clock.record(.woke, at: 0)
        clock.drop()
        #expect(clock.running(at: 1) == nil)
        #expect(clock.record(.fallingAsleep, at: 1) == nil)
    }
}

/// A sheet slides in and out inside a run of AppKit's own private mode
/// (`_NSMoveTimerRunLoopMode`), and the meter used to watch only the common
/// modes. It never saw that run begin, sleep between frames or end, so every
/// Export sheet read as one pass the length of its slide: 360ms opening and
/// 275ms closing on a still picture and a five minute video alike (measured
/// 2026-10-08, the-export-sheet-opens-without-a-stall). The meter watches that
/// mode too now, and says how much of a step was the slide.
@Suite("A window's slide is counted frame by frame")
struct WindowSlideSpanTests {

    @Test("The mode AppKit slides a sheet in is the one the meter watches")
    func modeName() {
        #expect(WindowSlideSpan.mode == "_NSMoveTimerRunLoopMode")
    }

    @Test("Time from entering the slide's run to leaving it is the slide")
    func spanIsCounted() {
        var span = WindowSlideSpan()
        span.entered(at: 1.0)
        span.left(at: 1.258)
        #expect(abs(span.total - 0.258) < 1e-9)
        span.entered(at: 2.0)
        span.left(at: 2.25)
        #expect(abs(span.total - 0.508) < 1e-9)
    }

    @Test("Leaving a slide never entered counts nothing")
    func unmatched() {
        var span = WindowSlideSpan()
        span.left(at: 5)
        #expect(span.total == 0)
        span.entered(at: 6)
        #expect(abs(span.total(at: 6.1) - 0.1) < 1e-9)
    }

    @Test("A reset forgets the total, and a slide under way counts on from the reset")
    func reset() {
        var span = WindowSlideSpan()
        span.entered(at: 1)
        span.left(at: 1.2)
        span.reset(at: 2)
        #expect(span.total == 0)
        span.entered(at: 3)
        span.reset(at: 3.1)
        span.left(at: 3.3)
        #expect(abs(span.total - 0.2) < 1e-9)
    }

    @Test("With the slide's run seen, its sleeps cut the pass: only the work before it is long")
    func slideFramesAreSeparatePasses() {
        var clock = MainThreadPassClock()
        var longest = 0.0
        func feed(_ m: MainThreadPassClock.Moment, _ t: Double) {
            if let d = clock.record(m, at: t) { longest = max(longest, d) }
        }
        feed(.woke, 0)
        feed(.enteredARun, 0.110)        // the sheet's slide begins
        for frame in 0..<30 {             // a frame drawn, then asleep till the next
            let t = 0.110 + Double(frame) * 0.0083
            feed(.woke, t)
            feed(.fallingAsleep, t + 0.001)
        }
        feed(.leftARun, 0.368)
        feed(.fallingAsleep, 0.370)
        #expect(abs(longest - 0.110) < 1e-9)
    }
}
