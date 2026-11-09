import Foundation
@testable import PhotonzMedia
import Synchronization
import Testing

/// A picture pass whose read stalls is started again once, on a fresh reader.
///
/// On 2026-11-09 a full test run caught an export's read stalled past its 30
/// second limit and answering on its own at 59.7 seconds: the decoder service
/// serving it sat idle, its hardware frame receiver waiting for a frame that
/// never came back, until the system's own timeout let it go. A fresh reader
/// asks for a fresh decoder session, so the export goes again from the start
/// rather than telling the person it failed.
@Suite("An export whose read stalls goes again once on a fresh reader")
struct StalledReadRetryTests {

    final class Calls: Sendable {
        let count = Mutex(0)
        let progress = Mutex<[Double]>([])
        func next() -> Int { count.withLock { $0 += 1; return $0 } }
    }

    @Test("A pass that stalls once is started again and finishes")
    func goesAgainOnce() async throws {
        let calls = Calls()
        try await VideoExporter.retryingAStalledRead(onProgress: nil) { _ in
            if calls.next() == 1 { throw VideoExporter.ExportError.readerGaveUp("stalled") }
        }
        #expect(calls.count.withLock { $0 } == 2)
    }

    @Test("A pass that stalls twice is reported as stalled, not tried a third time")
    func givesUpAfterTheSecond() async throws {
        let calls = Calls()
        await #expect(throws: VideoExporter.ExportError.self) {
            try await VideoExporter.retryingAStalledRead(onProgress: nil) { _ in
                _ = calls.next()
                throw VideoExporter.ExportError.readerGaveUp("stalled")
            }
        }
        #expect(calls.count.withLock { $0 } == 2)
    }

    @Test("Any other failure is reported at once, never tried again")
    func otherFailuresAreNotRetried() async throws {
        let calls = Calls()
        await #expect(throws: CancellationError.self) {
            try await VideoExporter.retryingAStalledRead(onProgress: nil) { _ in
                _ = calls.next()
                throw CancellationError()
            }
        }
        #expect(calls.count.withLock { $0 } == 1)
    }

    @Test("The bar never runs backwards when the pass starts again")
    func progressOnlyMovesForward() async throws {
        let calls = Calls()
        try await VideoExporter.retryingAStalledRead(onProgress: { value in
            calls.progress.withLock { $0.append(value) }
        }) { progress in
            let attempt = calls.next()
            for step in [0.1, 0.3, 0.5] { progress?(step) }
            if attempt == 1 { throw VideoExporter.ExportError.readerGaveUp("stalled") }
            for step in [0.7, 0.9] { progress?(step) }
        }
        let seen = calls.progress.withLock { $0 }
        #expect(seen == [0.1, 0.3, 0.5, 0.7, 0.9], "the bar read \(seen)")
    }
}
