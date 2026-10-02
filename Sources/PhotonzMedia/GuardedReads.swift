import Dispatch
import Foundation
import Synchronization

/// Blocking reads handed to a queue of their own, and given up on when they
/// stop answering.
///
/// `copyNextSampleBuffer()` waits on the system's media framework, and on
/// 2026-10-02 the test suite sat at 0% CPU for half an hour inside one in an
/// export. Two ways that read waits for ever were reproduced
/// (`find-out-why-the-test-suite-sometimes-hangs-in-a` in the queue):
///
/// * **It needs a free thread of Swift's shared pool to finish.** Fill fifteen
///   of sixteen with work that waits and read a video composition on the last:
///   the read sits in `FigSemaphoreWaitRelative` for good, the shape the stuck
///   suite showed. The same read on a queue of its own, pool still full, took
///   all 600 frames in 0.7s. So the read never runs on the pool.
/// * **The decoder runs in a process of its own and can stop answering.**
///   Pause it mid-read and the read waits with no error for as long as it stays
///   paused, and so does `cancelReading()` called from another thread. So the
///   caller is never left holding the wait: past `limit` it is told the read
///   stalled, and the read is abandoned to its queue, which lets it go if the
///   decoder ever answers.
///
/// The queue is serial, so the reader is only ever touched by one read at a
/// time, in the order asked.
struct GuardedReads: Sendable {

    /// A read that did not answer within the limit.
    struct Stalled: Error, Equatable {
        let seconds: TimeInterval
    }

    /// How long one read may take before it is called stuck.
    let limit: TimeInterval
    private let queue: DispatchQueue

    init(label: String, limit: TimeInterval) {
        self.limit = limit
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    /// `work`, run on the guard's queue. Throws `Stalled` once `limit` passes
    /// without an answer, and `CancellationError` the moment the waiting task
    /// is called off; either way the work itself is left to finish on its own.
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async throws -> T {
        let answer = Answer<T>()
        let limit = self.limit
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<T, Error>) in
                answer.wait(with: waiting)
                let giveUp = DispatchWorkItem { answer.give(.failure(Stalled(seconds: limit))) }
                DispatchQueue.global(qos: .userInitiated)
                    .asyncAfter(deadline: .now() + limit, execute: giveUp)
                queue.async {
                    let result = work()
                    giveUp.cancel()
                    answer.give(.success(result))
                }
            }
        } onCancel: {
            answer.give(.failure(CancellationError()))
        }
    }

    /// `work` queued behind every read asked for so far, never waited for.
    /// For clean-up that must not race a read still in flight, or be waited on
    /// when that read is stuck (`cancelReading()` on a stuck reader is stuck too).
    func afterwards(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}

/// One answer to one wait, whoever gets there first: the read, the clock or a
/// cancel. Whatever comes after the first is dropped.
private final class Answer<T: Sendable>: Sendable {
    private enum State {
        case unasked
        case waiting(CheckedContinuation<T, Error>)
        /// An answer that came before anybody was waiting (a cancel can).
        case early(Result<T, Error>)
        case answered
    }

    private let state = Mutex<State>(.unasked)

    func wait(with continuation: CheckedContinuation<T, Error>) {
        let early: Result<T, Error>? = state.withLock { state in
            if case .early(let result) = state {
                state = .answered
                return result
            }
            state = .waiting(continuation)
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func give(_ result: Result<T, Error>) {
        let waiting: CheckedContinuation<T, Error>? = state.withLock { state in
            switch state {
            case .unasked:
                state = .early(result)
                return nil
            case .waiting(let continuation):
                state = .answered
                return continuation
            case .early, .answered:
                return nil
            }
        }
        waiting?.resume(with: result)
    }
}
