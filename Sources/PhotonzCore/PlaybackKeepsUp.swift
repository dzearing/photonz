import Foundation

/// How far a playing picture may fall behind the playhead before a walk that
/// watches it play fails (`expectPlaybackNeverBlank`).
///
/// A late frame is not a blank one, since the frame before it is held, so a
/// walk used only to SAY how late it was. That let a full-screen Retina
/// recording play 17 looks in 24 half a second behind, on a green walk
/// (`a-full-screen-retina-recording-keeps-up-while-it`). A little is allowed,
/// for a machine busy with something else: two looks, each at most two frames
/// (66ms) behind, which a person watching does not see as a stutter.
public enum PlaybackKeepsUp {

    public static let lateLooksAllowed = 2
    public static let framesBehindAllowed = 2

    /// Why this playing failed to keep up, or nil when it kept up: which looks
    /// (numbered from 1) held an older frame, and the most frames behind any
    /// of them was.
    public static func problem(lateLooks: [Int], framesBehind: Int, looks: Int) -> String? {
        let which = lateLooks.map(String.init).joined(separator: ", ")
        if lateLooks.count > lateLooksAllowed {
            return "the picture fell behind the playhead at \(lateLooks.count) of \(looks) looks "
                + "(\(which)), at most \(lateLooksAllowed) may, and was up to \(framesBehind) frame(s) behind"
        }
        if framesBehind > framesBehindAllowed {
            return "the picture fell \(framesBehind) frames behind the playhead at look(s) \(which); "
                + "at most \(framesBehindAllowed) is a frame nobody sees stick"
        }
        return nil
    }
}
