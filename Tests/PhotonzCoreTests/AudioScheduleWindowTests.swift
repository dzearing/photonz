import Foundation
import Testing
@testable import PhotonzCore

/// What the sound engine has on it as a long edit plays (task
/// `find-out-whether-a-long-edit-goes-quiet-after-it`): every piece is on the
/// engine before its moment comes, however long the edit, and only a stretch
/// ahead of the playhead is held at once.
@Suite struct AudioScheduleWindowTests {

    typealias Span = AudioScheduleWindow.Span

    /// Back-to-back pieces `length` long from 0 to `total`.
    func row(every length: Int, upTo total: Int) -> [Span] {
        stride(from: 0, to: total, by: length).map { Span(startMS: $0, endMS: min(total, $0 + length)) }
    }

    /// Plays from `fromMS` to `toMS`, topping up every `tickMS`, and says at
    /// each tick which pieces sounding then are NOT on the engine.
    func missing(_ spans: [Span], fromMS: Int, toMS: Int, tickMS: Int,
                 budget: Int = AudioScheduleWindow.budget) -> [Int: [Int]] {
        var window = AudioScheduleWindow(spans: spans, fromMS: fromMS, budget: budget)
        var on = Set(window.start().add)
        var gaps: [Int: [Int]] = [:]
        var now = fromMS
        while now < toMS {
            now += tickMS
            let step = window.advance(toMS: now)
            on.formUnion(step.add)
            on.subtract(step.retire)
            let sounding = spans.indices.filter { spans[$0].startMS <= now && spans[$0].endMS > now }
            let absent = sounding.filter { !on.contains($0) }
            if !absent.isEmpty { gaps[now] = absent }
        }
        return gaps
    }

    @Test func aLongRowOfPiecesIsAlwaysOnTheEngineWhenItSounds() {
        // 200 pieces of six seconds: twenty minutes, four times the old budget.
        let spans = row(every: 6000, upTo: 1_200_000)
        #expect(missing(spans, fromMS: 0, toMS: 1_200_000, tickMS: 1000).isEmpty)
    }

    @Test func onlyAStretchAheadIsHeldAtOnce() {
        let spans = row(every: 6000, upTo: 1_200_000)
        var window = AudioScheduleWindow(spans: spans, fromMS: 0)
        let first = window.start()
        // The first look-ahead's worth, not the whole edit.
        #expect(first.add.count == AudioScheduleWindow.lookAheadMS / 6000 + 1)
        var held = Set(first.add)
        var most = held.count
        for now in stride(from: 1000, through: 1_200_000, by: 1000) {
            let step = window.advance(toMS: now)
            held.formUnion(step.add)
            held.subtract(step.retire)
            most = max(most, held.count)
        }
        #expect(most <= AudioScheduleWindow.lookAheadMS / 6000 + 2)
        #expect(window.leftOut.isEmpty)
        #expect(window.scheduled.isEmpty || window.scheduled.allSatisfy { spans[$0].endMS > 1_190_000 })
    }

    @Test func aPieceIsScheduledOnceAndRetiredOnceItHasFinished() {
        let spans = row(every: 6000, upTo: 120_000)
        var window = AudioScheduleWindow(spans: spans, fromMS: 0)
        var added = window.start().add
        var retired: [Int] = []
        for now in stride(from: 500, through: 130_000, by: 500) {
            let step = window.advance(toMS: now)
            added += step.add
            retired += step.retire
        }
        #expect(added.sorted() == Array(spans.indices))
        #expect(Set(added).count == added.count)
        #expect(retired.sorted() == Array(spans.indices))
        // Not before it has finished playing, with a little room for the
        // two clocks to disagree.
        var check = AudioScheduleWindow(spans: spans, fromMS: 0)
        _ = check.start()
        let atEnd = check.advance(toMS: 6000)
        #expect(!atEnd.retire.contains(0))
    }

    @Test func aSoundLongAfterThePressIsPutOnWhenItComesUp() {
        // Nothing in the first stretch: nothing at the press, and the one
        // sound goes on twenty seconds before it is due.
        let spans = [Span(startMS: 45_000, endMS: 50_000)]
        var window = AudioScheduleWindow(spans: spans, fromMS: 0)
        #expect(window.start().add.isEmpty)
        #expect(window.advance(toMS: 20_000).add.isEmpty)
        #expect(window.advance(toMS: 25_500).add == [0])
        #expect(missing(spans, fromMS: 0, toMS: 60_000, tickMS: 500).isEmpty)
    }

    @Test func playingFromTheMiddleLeavesOutWhatIsAlreadyOver() {
        let spans = row(every: 6000, upTo: 120_000)
        var window = AudioScheduleWindow(spans: spans, fromMS: 61_000)
        let first = window.start().add
        // 60-66 s is under way and is picked up part way in; 0-60 s is over.
        #expect(first.min() == 10)
        #expect(missing(spans, fromMS: 61_000, toMS: 120_000, tickMS: 1000).isEmpty)
        #expect(window.leftOut.isEmpty)
    }

    @Test func aStallLongerThanTheLookAheadPicksUpWhatIsStillSounding() {
        // The top-up did not run for a minute: the pieces that came and went
        // meanwhile were not heard, and say so; the one sounding now is put on.
        let spans = row(every: 6000, upTo: 300_000)
        var window = AudioScheduleWindow(spans: spans, fromMS: 0)
        _ = window.start()
        let step = window.advance(toMS: 90_000)
        #expect(step.add.contains(15)) // 90-96 s
        #expect(!step.add.contains(14))
        #expect(window.leftOut.count == 15 - (AudioScheduleWindow.lookAheadMS / 6000 + 1))
    }

    @Test func moreAliveAtOnceThanTheBudgetLeavesSomethingOutAndSaysSo() {
        // Ten pieces that all start at once in the middle of a long row.
        var spans = row(every: 6000, upTo: 600_000)
        spans += (0..<10).map { _ in Span(startMS: 300_500, endMS: 305_000) }
        spans.sort { $0.startMS < $1.startMS }
        var window = AudioScheduleWindow(spans: spans, fromMS: 0, budget: 8)
        var held = Set(window.start().add)
        var most = held.count
        for now in stride(from: 1000, through: 600_000, by: 1000) {
            let step = window.advance(toMS: now)
            held.formUnion(step.add)
            held.subtract(step.retire)
            most = max(most, held.count)
        }
        #expect(most <= 8)
        #expect(!window.leftOut.isEmpty)
        // Nothing before the pile-up is touched by it.
        #expect(window.leftOut.allSatisfy { spans[$0].endMS > 300_500 })
        #expect(window.leftOut.allSatisfy { spans[$0].startMS < 300_500 + AudioScheduleWindow.lookAheadMS })
    }

    @Test func theReferenceEditsArePlayedWholeFromTheStart() {
        // The edit the speed walk plays: from the start, every piece of
        // sound is on the engine at every second it sounds.
        for minutes in [20, 60] {
            let mix = ReferenceEdit.build(minutes: minutes).audioMix().filter(\.isAudible)
            let spans = AudioScheduleWindow.spans(of: mix)
            #expect(spans.count > AudioScheduleWindow.budget * 2)
            #expect(missing(spans, fromMS: 0, toMS: minutes * 60_000, tickMS: 1000).isEmpty,
                    "the \(minutes) minute edit")
        }
    }

    @Test func spansComeOutInTheOrderOfTheMixSortedByStart() {
        let id = UUID()
        let sound = SoundRef(id: UUID(), durationMS: 10_000)
        func segment(_ start: Int) -> AudioMixSegment {
            AudioMixSegment(layerID: id, sound: sound, startMS: start, lengthMS: 1000, sourceInMS: 0,
                            sourceLengthMS: 1000, speedPercent: 100, ramps: [], voice: 0)
        }
        let mix = [segment(5000), segment(1000), segment(3000)]
        let order = AudioScheduleWindow.order(of: mix)
        #expect(order.map { mix[$0].startMS } == [1000, 3000, 5000])
        #expect(AudioScheduleWindow.spans(of: order.map { mix[$0] }).map(\.startMS) == [1000, 3000, 5000])
    }
}
