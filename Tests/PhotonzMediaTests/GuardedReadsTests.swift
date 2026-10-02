import Dispatch
import Foundation
@testable import PhotonzMedia
import Testing

/// A read that blocks is never left to block for ever.
///
/// Reading a frame out of a movie waits on the system's media framework, and
/// on 2026-10-02 the test suite sat at 0% CPU for half an hour inside one such
/// read in an export test. Two ways it can wait for ever were reproduced: the
/// read needs a free thread of Swift's shared pool to finish, so on a full
/// pool it never does; and a decoder service that stops answering leaves it
/// waiting with no error at all. These check the guard that rules out both.
@Suite("A blocking read runs on its own queue and is given up on when it stops answering")
struct GuardedReadsTests {

    @Test("A read that answers hands its answer back")
    func answers() async throws {
        let reads = GuardedReads(label: "test.answers", limit: 5)
        let answer = try await reads.run { 42 }
        #expect(answer == 42)
    }

    @Test("Reads come back in the order they were asked for")
    func inOrder() async throws {
        let reads = GuardedReads(label: "test.order", limit: 5)
        var seen: [Int] = []
        for n in 0..<50 {
            seen.append(try await reads.run { n })
        }
        #expect(seen == Array(0..<50))
    }

    @Test("The read runs on the guard's own queue, not on Swift's shared pool")
    func offThePool() async throws {
        let reads = GuardedReads(label: "test.own-queue", limit: 5)
        let label = try await reads.run {
            String(cString: __dispatch_queue_get_label(nil))
        }
        #expect(label == "test.own-queue")
    }

    @Test("A read that never answers is given up on once the limit passes")
    func givesUp() async throws {
        let reads = GuardedReads(label: "test.stuck", limit: 0.3)
        // The read is let go only once the caller has its answer, so the
        // answer arriving at all is the proof the caller was not held. No
        // ceiling on the time: in the whole suite every test waits its turn
        // for a thread, and the slowest suites take two minutes.
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let started = Date()
        await #expect(throws: GuardedReads.Stalled(seconds: 0.3)) {
            try await reads.run { release.wait(); return 1 }
        }
        let waited = Date().timeIntervalSince(started)
        #expect(waited >= 0.3, "gave up before the limit, after \(waited)s")
    }

    @Test("A slow read inside the limit is still waited for")
    func slowButInTime() async throws {
        let reads = GuardedReads(label: "test.slow", limit: 2)
        let answer = try await reads.run { () -> Int in
            Thread.sleep(forTimeInterval: 0.2)
            return 7
        }
        #expect(answer == 7)
    }

    @Test("Calling the wait off stops it at once, however long the read takes")
    func cancelled() async throws {
        // A limit no test run reaches, and a read let go only after the wait
        // is answered: only the cancel can have answered it.
        let reads = GuardedReads(label: "test.cancelled", limit: 3600)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let waiting = Task { try await reads.run { release.wait(); return 1 } }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
    }

    @Test("Clean-up queued behind a stuck read waits for it, and never holds the caller")
    func afterwardsWaitsItsTurn() async throws {
        let reads = GuardedReads(label: "test.afterwards", limit: 0.2)
        let release = DispatchSemaphore(value: 0)
        let cleaned = DispatchSemaphore(value: 0)
        await #expect(throws: GuardedReads.Stalled(seconds: 0.2)) {
            try await reads.run { release.wait(); return 1 }
        }
        reads.afterwards { cleaned.signal() }
        #expect(await !signalled(cleaned, within: 0.2),
                "the clean-up ran while the read was still stuck")
        release.signal()
        #expect(await signalled(cleaned, within: 60),
                "the clean-up never ran once the read let go")
    }

    /// A semaphore waited on away from the shared pool, which a test must not
    /// hold while it waits.
    private func signalled(_ semaphore: DispatchSemaphore, within seconds: Double) async -> Bool {
        await OffThePool.run { semaphore.wait(timeout: .now() + seconds) == .success }
    }
}
