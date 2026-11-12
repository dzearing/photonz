import Foundation
@testable import PhotonzCore
import Testing

/// A request has five minutes, and a model that has gone quiet is noticed in
/// a minute and a half rather than waited out (task
/// `find-out-why-ask-sometimes-waits-five-minutes-fo`). Every "stall" the eval
/// recorded from 2026-10-23 to 2026-11-09 was the model answering throughout,
/// turn after turn, past the walk's five minutes; across 26,849 server tasks
/// a working server never went more than 37 s without news.
@Suite("A request ends inside its five minutes, and a quiet model is noticed")
struct AskRequestTimeTests {

    @Test("No planning round starts past the latest start, and a round still going is cut before five minutes")
    func rounds() {
        #expect(AskRequestTime.startsRound(at: 0))
        #expect(AskRequestTime.startsRound(at: AskRequestTime.latestRound - 1))
        #expect(!AskRequestTime.startsRound(at: AskRequestTime.latestRound))
        #expect(AskRequestTime.latestRound < AskRequestTime.roundCut)
        // What is planned still has to run inside the walk's 300 s.
        #expect(AskRequestTime.roundCut <= 270)
        // A moving icon's mend keeps its own, later bounds inside the same five minutes.
        #expect(AskRequestTime.roundCut >= AskMotionLook.latestStart)
    }

    @Test("Out of time with steps planned offers them; with none, it says it took too long")
    func outOfTime() {
        #expect(AskRequestTime.whenOutOfTime(stepsPlanned: 3) == .offerPlanned)
        #expect(AskRequestTime.whenOutOfTime(stepsPlanned: 0) == .tooSlow)
    }

    @Test("A drawing is not drawn again past the latest start: what landed stays")
    func revisions() {
        #expect(AskRequestTime.drawsAgain(at: 100))
        #expect(!AskRequestTime.drawsAgain(at: AskRequestTime.latestRound))
    }

    @Test("A model that never starts is quiet once the quiet time has passed since the request went")
    func neverStarts() {
        var watch = AskModelWatch(at: 10)
        watch.heard(nil, at: 30)
        watch.heard(nil, at: 60)
        #expect(!watch.stalled(at: 10 + AskModelWatch.quietSeconds - 1))
        #expect(watch.stalled(at: 10 + AskModelWatch.quietSeconds))
    }

    @Test("Reading and writing are news; the same count again is not")
    func news() {
        var watch = AskModelWatch(at: 0)
        watch.heard(AskModelProgress(read: 1024, written: 0), at: 5)
        watch.heard(AskModelProgress(read: 2048, written: 0), at: 40)
        watch.heard(AskModelProgress(read: 2048, written: 12), at: 70)
        #expect(!watch.stalled(at: 70 + AskModelWatch.quietSeconds - 1))
        watch.heard(AskModelProgress(read: 2048, written: 12), at: 100)
        watch.heard(AskModelProgress(read: 2048, written: 12), at: 150)
        #expect(watch.stalled(at: 70 + AskModelWatch.quietSeconds))
    }

    @Test("A gap between readings is not news, and nothing heard while it loads counts against it")
    func loading() {
        var watch = AskModelWatch(at: 0)
        watch.heard(AskModelProgress(read: 500, written: 0), at: 5)
        watch.heard(nil, at: 50)
        #expect(!watch.stalled(at: 94))
        // Loading the model has its own, longer bound: the clock starts again after it.
        watch.loading(at: 80)
        watch.loading(at: 200)
        #expect(!watch.stalled(at: 200 + AskModelWatch.quietSeconds - 1))
        #expect(watch.stalled(at: 200 + AskModelWatch.quietSeconds))
    }

    @Test("The quiet time is well past the longest a working server went without news")
    func measured() {
        // 37 s: the longest gap inside a working task across every server log
        // on this Mac, 2026-10-22 to 2026-11-12, under heavy contention.
        #expect(AskModelWatch.quietSeconds >= 2 * 37)
        #expect(AskModelWatch.quietSeconds <= 120)
    }

    @Test("A walk can give a request less time, and its bounds keep their places in it")
    func walkSeconds() throws {
        #expect(AskRequestTime.latestRound(within: nil) == AskRequestTime.latestRound)
        #expect(AskRequestTime.roundCut(within: nil) == AskRequestTime.roundCut)
        #expect(AskRequestTime.latestRound(within: 60) == 48)
        #expect(AskRequestTime.roundCut(within: 60) == 54)
        #expect(try PlaytestSetup(fields: ["askSeconds": 60]).askSeconds == 60)
        #expect(try PlaytestSetup(fields: ["askSeconds": 60]).isEmpty == false)
        #expect(try PlaytestSetup(fields: [:]).askSeconds == nil)
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askSeconds": 5]) }
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askSeconds": 301]) }
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askSeconds": true]) }
    }
}
