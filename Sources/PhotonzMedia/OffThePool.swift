import AVFoundation
import Foundation

/// Run work that blocks (decoding a file, cleaning it) on a queue of its own,
/// never on the pool of threads Swift's async work shares.
///
/// That pool has about one thread per core, and a decode that sits on one
/// while it waits for the system's media framework to hand back a buffer is a
/// thread nothing else can use. Enough of them at once and nothing runs at
/// all: the test suite hung on 2026-09-29 with eight file readers and a text
/// reader each holding a thread and waiting on work that needed one.
enum OffThePool {

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { done.resume(returning: try work()) } catch { done.resume(throwing: error) }
            }
        }
    }

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (done: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: work()) }
        }
    }
}

/// A file's track (its sound, or the pictures an export weighs), handed whole
/// to the one queue that reads it.
///
/// `AVAssetTrack` is not marked Sendable. It is safe to send here because the
/// caller loads it, hands it over and never touches it again: only the queue
/// reading it ever uses it.
struct HandedTrack: @unchecked Sendable {
    let track: AVAssetTrack
    let asset: AVAsset
}
