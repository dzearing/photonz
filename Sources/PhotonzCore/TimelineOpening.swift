import Foundation

/// **How the timeline under a document with time opens**, and what brings it up.
///
/// A recording opens to watch: the picture, the transport under it, and the
/// timeline tucked down to one row, the way QuickTime or Premiere's source
/// monitor opens a clip. Nothing is picked and no editing tool is in hand. The
/// tracks come up the moment you ask for them (the row, ⌥⌘T) or start an edit
/// (I, O, B, Q, W, ⌘K, ⌘T, Trim), and the last choice you made by hand is the
/// one the next recording opens with.
///
/// This replaced the fast lane (`docs/design/video-surface.md` §10.3), which
/// opened a fresh recording with the clip picked and Trim in hand. The user
/// turned it down on 2026-09-25: "When I open a video, it seems defaulted into
/// a trim workflow. I'd prefer to be in playback mode where the edit tools are
/// collapsed but can be expanded."
public enum TimelineOpening {

    /// Whether the timeline under `document` is open when its window first
    /// shows it.
    ///
    /// - Parameters:
    ///   - remembered: the last open or closed chosen by hand, nil when there
    ///     has never been one. Only an untouched recording follows it.
    ///   - forAGuide: the document is a guide's sample, whose cards point at
    ///     the tracks, so it opens with them showing.
    public static func opensOpen(_ document: PhotonzDocument, remembered: Bool?,
                                 forAGuide: Bool = false) -> Bool {
        if forAGuide { return true }
        // Something already done to it: you are coming back to an edit, and
        // the edit is on the timeline.
        guard document.isUntouchedRecording else { return true }
        return remembered ?? false
    }

    /// The name on the row the timeline leaves behind (`.tlrail .nm`).
    public static let railName = "Timeline"
    /// What the row says it does (`.tlrail .sp`).
    public static let railHint = "click to expand"

    /// What the row says between them (`.tlrail .sum`): the thing picked, then
    /// where the playhead is in how long, exactly as the mock writes it
    /// (`video.html`, "what the collapsed timeline row says").
    public static func railSummary(pickedName: String?, time: String, length: String) -> String {
        let clock = "\(time) / \(length)"
        guard let name = pickedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return clock }
        return "\(name)  ·  \(clock)"
    }
}

extension PhotonzDocument {

    /// A recording exactly as it came off the disk: one clip, one piece, all
    /// of it in play. Anything more (a second layer, a cut, a trim) means
    /// somebody has worked on it.
    public var isUntouchedRecording: Bool {
        guard hasTime, layers.count == 1, let only = layers.first, only.isClip,
              only.clipPieces?.isOnePlainPiece == true else { return false }
        return only.time?.spareBeforeMS == 0 && only.time?.spareAfterMS == 0
    }
}

extension TimelineKeyCommand {

    /// Whether this key starts an edit, and so brings a tucked-away timeline
    /// up to show it. Watching keys (space, J/K/L, the arrows, Home and End)
    /// leave it where it is, because watching is what the tucked-away state
    /// is for. V hands the press on to the canvas's arrow, so it is not one.
    public var opensTheTimeline: Bool {
        switch self {
        case .playPause, .shuttle, .stepFrames, .editPoint, .goToStart, .goToEnd,
             .selectTool, .trackSelectForwardTool:
            return false
        case .markIn, .markOut, .clearIn, .clearOut, .addMarker, .splitAtPlayhead, .lift,
             .rippleDelete, .extractMarked, .liftMarked, .rippleTrimToPlayhead,
             .applyDefaultTransition, .toggleSnapping, .bladeTool, .zoomIn, .zoomOut, .zoomToFit:
            return true
        }
    }
}
