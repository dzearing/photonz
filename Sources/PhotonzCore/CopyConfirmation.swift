import Foundation

/// The "Copied" notice (Next, `next-measure-panel`): the glass pill at the
/// bottom of the canvas that answers Copy as Spec List, Copy Measurement and
/// Copy Image.
///
/// Nothing else on screen changes when text lands on the clipboard, so without
/// it a person cannot tell whether the key was taken. It is a glance, not a
/// banner: the verdict in its own weight, one line saying what was copied,
/// and it fades on its own after `lifetime`. It shares the canvas-bottom slot
/// with the Measure mode hint (`MeasureModeHint`) so two pills never stack.
///
/// Session chrome only: it never enters the document or the undo history.
public struct CopyConfirmation: Hashable, Sendable {
    /// What landed on the clipboard, so the line reads differently for a
    /// whole list and for one row. Counts are what the text carries: the
    /// spec list lists visible measurements only, and a list whose rows are
    /// all hidden still copies its header.
    public enum Subject: Hashable, Sendable {
        case specList(measurements: Int)
        case measurements(count: Int)
        /// Copy Image: the picture, plus the spec list when `measurements`
        /// is above zero (`CompositeCopy`).
        case image(measurements: Int)
    }

    /// How long the pill stays up before fading. Enough to catch, short enough
    /// that a fluent user is never waiting for it to leave.
    public static let lifetime: TimeInterval = 1.6

    public var subject: Subject
    public var shownAt: Date

    public init(subject: Subject, shownAt: Date) {
        self.subject = subject
        self.shownAt = shownAt
    }

    /// Whether the pill should still be on screen at `now`. Strictly inside the
    /// window, so a clock that runs backwards cannot pin it up forever.
    public func isLive(at now: Date) -> Bool {
        let age = now.timeIntervalSince(shownAt)
        return age >= 0 && age < Self.lifetime
    }

    /// The same pill, re-shown for a new copy with its clock restarted. Two
    /// quick copies keep one pill up that fades from the last one.
    public func reshown(as subject: Subject, at now: Date) -> CopyConfirmation {
        CopyConfirmation(subject: subject, shownAt: now)
    }

    /// The verdict, set in its own weight at the head of the pill.
    public var title: String { "Copied" }

    /// What was copied, in plain words.
    public var detail: String {
        switch subject {
        case .specList(let count):
            return "Spec list with \(count == 0 ? "no visible measurements" : Self.measurementPhrase(count))"
        case .measurements(let count):
            return Self.measurementPhrase(count)
        case .image(let count):
            return count == 0 ? "Image" : "Image and spec list with \(Self.measurementPhrase(count))"
        }
    }

    /// "1 measurement" / "N measurements".
    private static func measurementPhrase(_ count: Int) -> String {
        count == 1 ? "1 measurement" : "\(count) measurements"
    }
}
