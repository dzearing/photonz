import Foundation

/// How a save that takes real time tells you it is happening, and that it
/// worked.
///
/// Saving a trimmed recording re-encodes it, which can take anything from a
/// blink to several seconds. Before this, the whole report was a small arrow on
/// the floating controller swapping itself for a 28 point spinner and then
/// disappearing, which is why it was reported as "I click Save and it does
/// nothing" (2026-09-19). Copying a recording already says so in the
/// bottom-right toast stack; saving says so the same way.
///
/// Two rules live here rather than in the window, because they are the whole
/// behaviour and they can be checked without one:
///
/// - **Short saves stay quiet.** A progress toast that flashes up for a fifth
///   of a second is worse than no progress toast: it is a flicker in the corner
///   of your eye that is gone before it can be read. Nothing is shown until a
///   save has been running longer than `quietWindow`.
/// - **The line names the recording.** A confirmation that says "Saved" tells
///   you a save happened somewhere; with three video windows open that is not
///   the same as telling you which.
public enum SaveFeedback {
    /// How long a save may run before anything is drawn about it. A save that
    /// finishes inside this window says nothing until it is done.
    public static let quietWindow: TimeInterval = 0.5

    /// Longest name either line will print before it is shortened.
    public static let nameLimit = 28

    /// Whether a save that has been running this long should be showing
    /// progress by now.
    public static func showsProgress(afterRunningFor seconds: TimeInterval) -> Bool {
        seconds >= quietWindow
    }

    /// The caption over the progress bar while the save runs.
    public static func progressTitle(for name: String) -> String {
        "Saving \(shortName(name))\u{2026}"
    }

    /// The line under the thumbnail once the recording is written.
    public static func savedMessage(for name: String) -> String {
        "\(shortName(name)) saved"
    }

    /// A file name cut down to fit a toast, from the middle, so the front still
    /// says which recording and the tail still says what kind of file it is.
    public static func shortName(_ name: String, limit: Int = nameLimit) -> String {
        guard name.count > limit, limit > 3 else { return name }
        // Two thirds to the front, one third to the tail. An even split cut
        // "Screen Recording 2026-09-19 at 10.14.22.mov" before the word
        // "Recording" had finished, which is the part that says which file this
        // is; the tail only has to carry the time and the extension.
        let keep = limit - 1 // the ellipsis takes a character
        let tail = keep / 3
        let head = keep - tail
        return name.prefix(head) + "\u{2026}" + name.suffix(tail)
    }

    /// Share of the bar the encode is allowed to fill. The rest is the work a
    /// commit still has to do afterwards: preserving the untouched original and
    /// swapping the new media in. A bar that hits 100% and then waits reads as
    /// stuck.
    public static let encodeShare = 0.92

    /// The whole commit's progress, from the encoder's own.
    public static func commitFraction(encoded: Double) -> Double {
        guard encoded.isFinite else { return 0 }
        return min(1, max(0, encoded)) * encodeShare
    }
}
