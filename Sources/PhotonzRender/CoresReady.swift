import Foundation
import Synchronization

/// Keeps one core running while a stroke is under way, so each move's dabs are
/// worked out at the speed the cores reach under load.
///
/// A hand sends a move every 8 to 16 ms, and a big brush lays a dab only every
/// few moves (one every 50 points at 500 points). Between dabs the cores sat
/// idle and the system slowed them down, so the dab that came next ran slow:
/// the same 500 point oil dab cost 4.8 ms with the moves back to back, 10.7 ms
/// with 8 ms between them, and 5.3 ms with one core kept running beside it
/// (2026-10-30, a release build of this code on an M4 Max).
///
/// It never outlives the hand. Every move asks for `hold` more; with no move
/// for that long the core stops by itself, and `letGo` stops it at once. Only
/// one core is ever kept, however many moves ask.
public final class CoresReady: Sendable {
    public static let shared = CoresReady(hold: 0.25)

    /// How long one move keeps the core running, in seconds.
    public let hold: Double

    private struct State {
        /// Uptime, in nanoseconds, the core runs until.
        var until: UInt64 = 0
        var running = false
        var started = 0
    }
    private let state = Mutex(State())

    public init(hold: Double) {
        self.hold = hold
    }

    /// Whether a core is being kept running now.
    public var isKeeping: Bool { state.withLock { $0.running } }

    /// How many times a core has been set running: once per stretch of moves.
    var started: Int { state.withLock { $0.started } }

    /// A move: keep a core running for `hold` from now.
    public func keep() {
        let until = Self.now() + UInt64(max(0, hold) * 1e9)
        let start = state.withLock { s -> Bool in
            s.until = max(s.until, until)
            guard !s.running else { return false }
            s.running = true
            s.started += 1
            return true
        }
        guard start else { return }
        let thread = Thread { [self] in run() }
        thread.name = "Photonz cores ready"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// The stroke is done: stop now.
    public func letGo() {
        state.withLock { $0.until = 0 }
    }

    private func run() {
        while true {
            let now = Self.now()
            let until = state.withLock { s -> UInt64? in
                guard now < s.until else {
                    s.running = false
                    return nil
                }
                return s.until
            }
            guard let until else { return }
            // Busy for a twentieth of a millisecond at a time, then look again.
            let slice = min(until, now + 50_000)
            while Self.now() < slice {}
        }
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}
