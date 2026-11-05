import Foundation

/// Whether a copy really reached the clipboard.
///
/// A copy that did not used to be silent, which is the worst way for it to
/// fail: the person pastes the picture from before, or nothing, and has no way
/// to tell why. The clipboard is read back after a copy, and when it holds no
/// picture in time the person is told and offered Copy Again.
public enum ClipboardProof {

    public enum Verdict: Equatable, Sendable {
        /// The picture can be read back.
        case held
        /// Something newer is on the clipboard, here or from any other app.
        case movedOn
        case keepWaiting
        /// The limit passed with no picture to read.
        case missed
    }

    /// How long a copy has to become readable.
    public static let limit: TimeInterval = 2

    public static let noticeTitle = "Screenshot not copied"
    public static let noticeDetail = "A paste won't get this picture"
    public static let noticeAction = "Copy Again"

    /// `wrote` is the clipboard's change count when the copy went up, `now` the
    /// count at this look. A clipboard that has moved on says nothing about the
    /// copy, so it is never called a miss.
    public static func verdict(wrote: Int, now: Int, pictureReadable: Bool, elapsed: TimeInterval) -> Verdict {
        guard now == wrote else { return .movedOn }
        if pictureReadable { return .held }
        return elapsed >= limit ? .missed : .keepWaiting
    }
}
