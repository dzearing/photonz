import Foundation
@testable import PhotonzCore
import Testing

/// A request sent while Ask is still working waits its turn, and can be
/// cancelled before it starts (the user, 2026-10-20: "if I type a message
/// while its working, it doesn't queue the message. It should queue and let me
/// cancel in the agent ux if it hasn't started").
@Suite("Ask: requests sent while it works wait in line")
struct AskRequestLineTests {

    @Test("Requests come out in the order they were sent")
    func firstInFirstOut() {
        var line = AskRequestLine()
        line.add("add a red circle")
        line.add("make it bigger")
        line.add("move it left")
        let order = [line.next(), line.next(), line.next(), line.next()].map { $0?.words }
        #expect(order == ["add a red circle", "make it bigger", "move it left", nil])
        #expect(line.isEmpty)
    }

    @Test("Words are trimmed, and a blank request never joins the line")
    func blankWordsAreNotKept() {
        var line = AskRequestLine()
        let blank = line.add("   \n ")
        #expect(blank == nil)
        #expect(line.isEmpty)
        let kept = line.add("  add a star \n")
        #expect(kept?.words == "add a star")
        #expect(line.waiting.map(\.words) == ["add a star"])
    }

    @Test("A cancelled request leaves the line and never comes out of it")
    func cancelledNeverRuns() throws {
        var line = AskRequestLine()
        line.add("first")
        let added = line.add("second")
        let second = try #require(added)
        line.add("third")
        let cancelled = line.cancel(second.id)
        let again = line.cancel(second.id)
        #expect(cancelled && !again)
        let order = [line.next(), line.next(), line.next()].map { $0?.words }
        #expect(order == ["first", "third", nil])
    }

    @Test("Two requests with the same words are two requests, each cancelled on its own")
    func sameWordsTwice() throws {
        var line = AskRequestLine()
        let first = line.add("add a cat")
        let second = line.add("add a cat")
        let a = try #require(first)
        let b = try #require(second)
        #expect(a.id != b.id)
        line.cancel(a.id)
        #expect(line.waiting.map(\.id) == [b.id])
    }

    @Test("Shown newest first, like the change rows under them")
    func shownNewestFirst() {
        var line = AskRequestLine()
        line.add("first")
        line.add("second")
        #expect(line.shown.map(\.words) == ["second", "first"])
    }

    @Test("Clearing the line drops every waiting request")
    func clearDropsAll() {
        var line = AskRequestLine()
        line.add("first")
        line.add("second")
        line.clear()
        let next = line.next()
        #expect(line.isEmpty && next == nil)
    }
}
