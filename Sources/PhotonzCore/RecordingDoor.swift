import Foundation

/// The one way in to a recording, and what the app says when it cannot take it.
///
/// Opening a recording used to be an act of faith: the window opened first and
/// the file was read afterwards, so a recording that had been moved, deleted or
/// was still landing on disk produced a window that never became anything. This
/// is the check that happens BEFORE a window opens, and the plain words that go
/// in the corner when the answer is no.
///
/// Pure: the app reads the three facts off the file (`RecordingFileFacts`) and
/// asks here what they mean.
public enum RecordingOpenState: Equatable, Sendable {
    /// There is a playable recording at that path. Open it.
    case ready
    /// Nothing is there. Moved, deleted, or on a disk that is not mounted.
    case gone
    /// Something is there and it is still being written, so it cannot be played
    /// yet. Worth waiting for.
    case stillWriting
    /// Something is there, it is not growing, and nothing in it can be played.
    case unplayable
}

/// What the app could learn about the file without opening a window for it.
public struct RecordingFileFacts: Equatable, Sendable {
    /// Whether anything is at that path at all.
    public var exists: Bool
    /// Size in bytes; 0 for a file that has only just been created.
    public var byteCount: Int
    /// Whether the file got bigger between two looks a moment apart. Only ever
    /// sampled when the length could not be read, so the ordinary case (a
    /// recording that plays) costs nothing.
    public var isGrowing: Bool
    /// The recording's length in milliseconds, or nil when the file would not
    /// give one up.
    public var durationMS: Int?

    public init(exists: Bool, byteCount: Int = 0, isGrowing: Bool = false, durationMS: Int? = nil) {
        self.exists = exists
        self.byteCount = byteCount
        self.isGrowing = isGrowing
        self.durationMS = durationMS
    }
}

public enum RecordingDoor {
    /// What those facts mean for opening.
    ///
    /// Order matters: a file that is growing is still being written even if a
    /// length can already be read off it, because the length it gives is the
    /// length so far and the window would open on half a recording.
    public static func state(of facts: RecordingFileFacts) -> RecordingOpenState {
        guard facts.exists else { return .gone }
        if facts.isGrowing { return .stillWriting }
        guard let duration = facts.durationMS, duration > 0 else { return .unplayable }
        return .ready
    }

    /// How long a file may keep landing before the app stops waiting for it.
    /// Twenty seconds is long enough for a screen recording being copied in over
    /// a network share and short enough that a stuck file does not hold a person
    /// there wondering.
    public static let patienceSeconds: TimeInterval = 20

    /// How far apart the two size samples are taken. Long enough for a writer to
    /// have written something, short enough not to be felt.
    public static let growthSampleSeconds: TimeInterval = 0.4

    /// What the corner of the screen says. `name` is the file's own name, which
    /// is what the person picked, so it is what they are told about.
    public static func message(for state: RecordingOpenState, name: String) -> (title: String, detail: String)? {
        switch state {
        case .ready:
            return nil
        case .gone:
            return ("\(name) is not there any more",
                    "It has been moved or deleted since it was last seen.")
        case .stillWriting:
            return ("\(name) is still being saved",
                    "It opens as soon as the file has finished landing.")
        case .unplayable:
            return ("\(name) could not be opened",
                    "The file is there, but there is no recording in it to play.")
        }
    }

    /// What the corner says when a wait ran out: the file never stopped landing.
    public static func gaveUpMessage(name: String) -> (title: String, detail: String) {
        ("\(name) is still not finished",
         "It was still being written after \(Int(patienceSeconds)) seconds. Try again once it has landed.")
    }
}

/// Which files the app treats as a recording when one is handed to it.
///
/// The same list the capture folder scan uses (`CaptureLibrary.videoExtensions`),
/// asked of a URL rather than of a bare extension, so every door into the app
/// agrees on what a recording is.
public enum RecordingFiles {
    public static func isRecording(_ url: URL) -> Bool {
        CaptureLibrary.videoExtensions.contains(url.pathExtension.lowercased())
    }
}
