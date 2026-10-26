import Dispatch
import Foundation
import Synchronization

/// Where every text recognition runs: on a queue of its own, never on the
/// shared pool Swift's async work runs on, and only a few at a time.
///
/// The recogniser hands part of each read to another thread at the priority of
/// whoever asked, and waits for it. Asked from the shared pool, that is the
/// priority every pool thread runs at, and once every pool thread is waiting
/// inside a read there is no thread left at that priority to give it: on
/// 2026-10-12 sixteen reads at once on a sixteen core Mac sat at 0% CPU for
/// good, with nothing else running. A plain `DispatchQueue.global().async` from
/// a full pool never ran either, and neither did a read on a plain `Thread`.
/// The same read handed to a `.userInitiated` queue, the pool still full,
/// answered in 0.8s.
///
/// So the read is handed here and the caller waits for it. The caller's own
/// thread still waits, but nothing the read needs runs at its priority any
/// more. `width` keeps the lane's own waiting threads to a few, so the reads it
/// hands on always find a thread at the lane's priority too.
///
/// The main thread reads where it is: it runs at a priority of its own, which
/// the pool never fills, and waiting on a lower priority there is a hang risk
/// the system warns about.
///
/// From macOS 27 that is not enough on its own: the recogniser also needs a
/// free thread on the pool itself, and a read on a lane thread never answered
/// while every pool thread was blocked (2026-10-26). A caller waiting here
/// still blocks its own thread, so many reads asked for at once from the pool
/// can fill it again. `offThePool` is the answer for those: the whole read,
/// lane and all, is handed to a queue of its own and the asking task is
/// suspended rather than blocked, so the pool keeps its threads.
///
/// `TextReadsOnAFullPoolTests` is the check.
enum RecogniserLane {

    /// How many reads may be in the recogniser at once. A quarter of the
    /// cores: reading a page spread across the cores costs about half what one
    /// after another does, and four at once keeps most of that.
    static let width = max(2, ProcessInfo.processInfo.activeProcessorCount / 4)

    private static let gate = DispatchSemaphore(value: width)
    private static let queue = DispatchQueue(label: "photonz.text-recogniser",
                                             qos: .userInitiated, attributes: .concurrent)

    /// A read that never handed its answer back, which the queue makes
    /// impossible; here so the lane holds no force unwrap.
    struct Unanswered: Error {}

    /// Where `offThePool` runs its work: never Swift's shared pool, and as
    /// many threads as are waiting, since each spends its time in `gate`.
    private static let waiting = DispatchQueue(label: "photonz.text-recogniser.waiting",
                                               qos: .userInitiated, attributes: .concurrent)

    /// `work`, run on a thread that is not one of Swift's shared pool, with the
    /// asking task suspended until it answers instead of holding its thread.
    static func offThePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            waiting.async { continuation.resume(returning: work()) }
        }
    }

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> Result<T, any Error>) -> Result<T, any Error> {
        if Thread.isMainThread { return work() }
        gate.wait()
        defer { gate.signal() }
        let answer = Mutex<Result<T, any Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        queue.async {
            let result = work()
            answer.withLock { $0 = result }
            done.signal()
        }
        done.wait()
        return answer.withLock { $0 } ?? .failure(Unanswered())
    }
}
