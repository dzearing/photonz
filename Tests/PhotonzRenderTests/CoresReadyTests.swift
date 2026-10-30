import Foundation
import Testing
@testable import PhotonzRender

/// While a stroke is under way one core is kept running, so the next move's
/// dabs are worked out at full speed (`CoresReady`). A hand sends a move every
/// 8 to 16 ms and a big brush lays a dab only every few moves, so between dabs
/// the cores went idle and slowed down: the same 500 point oil dab took 4.8 ms
/// with the moves back to back and 10.7 ms with 8 ms between them, and 5.3 ms
/// with one core kept running beside it (2026-10-30). It must never outlive
/// the hand: it stops by itself a moment after the last move.
@Suite("Cores kept ready", .serialized)
struct CoresReadyTests {

    private func waitUntil(_ seconds: Double, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if done() { return true }
            usleep(5000)
        }
        return done()
    }

    @Test func aMoveKeepsACoreRunningAndItStopsByItself() {
        let ready = CoresReady(hold: 0.1)
        ready.keep()
        #expect(ready.isKeeping)
        #expect(waitUntil(2) { !ready.isKeeping }, "still running a while after the last move")
    }

    @Test func manyMovesShareOneCore() {
        let ready = CoresReady(hold: 0.2)
        for _ in 0..<200 { ready.keep() }
        #expect(ready.started == 1)
        ready.letGo()
    }

    @Test func eachMoveHoldsItLonger() {
        let ready = CoresReady(hold: 0.15)
        let end = Date().addingTimeInterval(0.4)
        while Date() < end {
            ready.keep()
            usleep(20_000)
        }
        // Moves kept coming for longer than one hold: still the one core.
        #expect(ready.isKeeping)
        #expect(ready.started == 1)
        ready.letGo()
    }

    @Test func lettingGoStopsItAtOnce() {
        let ready = CoresReady(hold: 30)
        ready.keep()
        ready.letGo()
        #expect(waitUntil(0.5) { !ready.isKeeping })
    }

    @Test func aMoveAfterItStoppedStartsItAgain() {
        let ready = CoresReady(hold: 0.05)
        ready.keep()
        #expect(waitUntil(2) { !ready.isKeeping })
        ready.keep()
        #expect(ready.isKeeping)
        #expect(ready.started == 2)
        ready.letGo()
    }
}
