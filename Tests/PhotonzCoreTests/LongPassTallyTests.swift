import Testing
@testable import PhotonzCore

/// A guarded wait over a stretch of playback says how many passes of the main
/// thread ran past its limit, not only the longest one: one 60 ms pass in
/// twenty seconds and sixty of them are different news
/// (`playing-a-five-minute-captioned-recording-never`).
@Suite("Counting the passes that ran past a limit")
struct LongPassTallyTests {

    @Test("passes at or over the limit are counted, shorter ones are not")
    func counts() {
        var tally = LongPassTally()
        tally.record(ms: 12, atMS: 0)
        tally.record(ms: 50, atMS: 100)
        tally.record(ms: 49.9, atMS: 200)
        tally.record(ms: 71.2, atMS: 300)
        #expect(tally.count(atOrOverMS: 50) == 2)
        #expect(tally.count(atOrOverMS: 10) == 4)
        #expect(tally.count(atOrOverMS: 80) == 0)
    }

    @Test("a pass shorter than the floor is not kept at all")
    func floor() {
        var tally = LongPassTally(floorMS: 16)
        tally.record(ms: 15.9, atMS: 0)
        tally.record(ms: 16, atMS: 10)
        #expect(tally.count(atOrOverMS: 0) == 1)
    }

    @Test("it says how many and lists the longest first, a few of them")
    func summary() {
        var tally = LongPassTally()
        for (index, ms) in [55.0, 90, 61, 70, 52, 12].enumerated() {
            tally.record(ms: ms, atMS: Double(index) * 1000)
        }
        #expect(tally.summary(atOrOverMS: 50, listing: 3)
                    == "5 passes at or over 50ms: 90ms at 1000, 70ms at 3000, 61ms at 2000 and 2 more")
        #expect(tally.summary(atOrOverMS: 100, listing: 3) == "no pass at or over 100ms")
        var one = LongPassTally()
        one.record(ms: 60, atMS: 5)
        #expect(one.summary(atOrOverMS: 50, listing: 3) == "1 pass at or over 50ms: 60ms at 5")
    }

    @Test("starting again forgets every pass")
    func reset() {
        var tally = LongPassTally()
        tally.record(ms: 80, atMS: 0)
        tally.reset()
        #expect(tally.count(atOrOverMS: 0) == 0)
    }

    @Test("it keeps a bounded number of passes, and still counts every one")
    func bounded() {
        var tally = LongPassTally(keeping: 10)
        for index in 0..<25 { tally.record(ms: 60, atMS: Double(index)) }
        #expect(tally.count(atOrOverMS: 50) == 25)
        #expect(tally.kept.count == 10)
    }
}
