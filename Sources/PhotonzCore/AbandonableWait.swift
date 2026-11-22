import Foundation
import Synchronization

/// Waiting for a task the waiter does not own, in a way the waiter can walk
/// away from.
///
/// `await task.value` on an unstructured task ignores the waiter's own
/// cancellation: the waiter is stuck until the task ends. That is right when
/// the task's work belongs to the waiter alone, and wrong when the task is
/// shared, like a model loading into memory for whichever request needs it
/// next. A request stopped during that load has to stop waiting at once, and
/// the load has to carry on for the request behind it.
public enum AbandonableWait {

    /// The value `task` ends with, or `CancellationError` as soon as the
    /// calling task is cancelled. `task` itself is never cancelled here.
    public static func value<T: Sendable>(of task: Task<T, Error>) async throws -> T {
        let once = OnceResumed<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.hold(continuation)
                Task { once.resume(with: await task.result) }
            }
        } onCancel: {
            once.resume(with: .failure(CancellationError()))
        }
    }
}

/// A continuation resumed exactly once, by whichever comes first: the task
/// ending or the waiter being cancelled. Either may arrive before the
/// continuation is held.
private final class OnceResumed<T: Sendable>: Sendable {
    private enum State {
        case empty
        case holding(CheckedContinuation<T, Error>)
        /// Resumed, or an outcome arrived early and waits to be handed over.
        case settled(Result<T, Error>?)
    }

    private let state = Mutex<State>(.empty)

    func hold(_ continuation: CheckedContinuation<T, Error>) {
        let early: Result<T, Error>? = state.withLock { state in
            switch state {
            case .empty:
                state = .holding(continuation)
                return nil
            case .settled(let outcome):
                state = .settled(nil)
                return outcome
            case .holding:
                return nil
            }
        }
        if let early { continuation.resume(with: early) }
    }

    func resume(with outcome: Result<T, Error>) {
        let held: CheckedContinuation<T, Error>? = state.withLock { state in
            switch state {
            case .empty:
                state = .settled(outcome)
                return nil
            case .holding(let continuation):
                state = .settled(nil)
                return continuation
            case .settled:
                return nil
            }
        }
        held?.resume(with: outcome)
    }
}
