import Foundation

/// When a stopped recording's file is finished, so it can go into history.
///
/// macOS closes a recording's file on its own time after Stop, and with sound
/// from the Mac and the microphone together that time is long: about 0.45 s
/// for every second recorded (measured 2026-10-10: 1.8 s for 3 s, 4.6 s for
/// 10 s, 20 s for 45 s). The recorder used to stop waiting 400 ms after the
/// stream stopped and hand the file over anyway, so history listed a file with
/// no recording in it yet: the tile went blank and opening it said it could not
/// be opened or was still being saved. Letting go of the writer that early also
/// meant macOS never said it had finished.
///
/// So time alone is never evidence. A file is finished when the writer says so,
/// or when two looks in a row find it playable and the same size (the writer's
/// word can go missing). It is given up on only when it has not changed at all
/// for longer than closing it could take (`patience`), and is handed over then
/// as it is, since a recording stuck forever in "saving" is worse.
///
/// Pure: the recorder reports what it hears and sees, and asks here.
public struct RecordingFileClose: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        /// The file is complete. Hand it over.
        case finished
        /// The writer said it failed. There may be no file.
        case failed
        /// Nothing changed for longer than closing could take.
        case gaveUp
    }

    /// How often the recorder looks at the file while it waits.
    public static let lookInterval: TimeInterval = 0.5

    /// How long a file may sit unchanged and unplayable before the wait is
    /// given up: a minute on top of the recording's own length, which is more
    /// than twice what macOS was measured taking.
    public static func patience(recordedSeconds: TimeInterval) -> TimeInterval {
        60 + max(0, recordedSeconds)
    }

    public private(set) var verdict: Verdict?
    private let patience: TimeInterval
    private var lastLook: RecordingFileFacts?
    private var lastChangeAt: TimeInterval = 0

    public init(recordedSeconds: TimeInterval) {
        patience = Self.patience(recordedSeconds: recordedSeconds)
    }

    /// The writer said the file is closed.
    public mutating func writerFinished() {
        if verdict == nil { verdict = .finished }
    }

    /// The writer said it failed.
    public mutating func writerFailed() {
        if verdict == nil { verdict = .failed }
    }

    /// A look at the file `seconds` after Stop.
    public mutating func looked(at facts: RecordingFileFacts, after seconds: TimeInterval) {
        guard verdict == nil else { return }
        defer { lastLook = facts }
        guard let previous = lastLook, previous.exists == facts.exists, previous.byteCount == facts.byteCount else {
            lastChangeAt = seconds
            return
        }
        if facts.exists, RecordingDoor.state(of: facts) == .ready,
           RecordingDoor.state(of: previous) == .ready {
            verdict = .finished
        } else if seconds - lastChangeAt > patience {
            verdict = .gaveUp
        }
    }
}
