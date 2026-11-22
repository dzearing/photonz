import Foundation
import PhotonzCore
import Testing

/// A wait that the waiter can walk away from (task
/// `stop-while-ask-s-model-is-still-loading-lets-the`). Ask's model loads in a
/// task of its own, shared by every request that needs it; a request that is
/// stopped while it loads has to stop waiting at once, so the request behind
/// it can start, while the load itself carries on for that next request.
@Suite("A wait the waiter can walk away from")
struct AbandonableWaitTests {

    @Test("hands back the value the task ends with")
    func handsBackTheValue() async throws {
        let task = Task<Int, Error> { 42 }
        #expect(try await AbandonableWait.value(of: task) == 42)
    }

    @Test("hands back the error the task ends with")
    func handsBackTheError() async {
        struct Broke: Error {}
        let task = Task<Int, Error> { throw Broke() }
        await #expect(throws: Broke.self) { try await AbandonableWait.value(of: task) }
    }

    @Test("a cancelled waiter stops waiting at once, and the task carries on")
    func cancelledWaiterStopsAtOnce() async throws {
        let release = Gate()
        let task = Task<Int, Error> {
            await release.wait()
            return 7
        }
        let waiter = Task<Result<Int, Error>, Never> {
            do { return .success(try await AbandonableWait.value(of: task)) } catch { return .failure(error) }
        }
        try await Task.sleep(for: .milliseconds(50))
        let cancelled = Date()
        waiter.cancel()
        let result = await waiter.value
        #expect(Date().timeIntervalSince(cancelled) < 1)
        guard case .failure(let error) = result else {
            Issue.record("the waiter should have given up, it got \(result)")
            return
        }
        #expect(error is CancellationError)
        // The task was not cancelled with its waiter: the next waiter gets its value.
        #expect(!task.isCancelled)
        await release.open()
        #expect(try await AbandonableWait.value(of: task) == 7)
    }

    @Test("a waiter already cancelled gives up without waiting")
    func alreadyCancelled() async {
        let release = Gate()
        let task = Task<Int, Error> {
            await release.wait()
            return 1
        }
        let waiter = Task<Bool, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await AbandonableWait.value(of: task)
                return false
            } catch {
                return error is CancellationError
            }
        }
        #expect(await waiter.value)
        await release.open()
        _ = try? await task.value
    }

    @Test("many waiters on one task each get its value")
    func manyWaiters() async throws {
        let release = Gate()
        let task = Task<Int, Error> {
            await release.wait()
            return 3
        }
        let waiters = (0..<20).map { _ in Task { try await AbandonableWait.value(of: task) } }
        try await Task.sleep(for: .milliseconds(20))
        await release.open()
        for waiter in waiters { #expect(try await waiter.value == 3) }
    }
}

/// Holds whoever waits until it is opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
