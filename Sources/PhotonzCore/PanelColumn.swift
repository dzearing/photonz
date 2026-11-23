import CoreGraphics

/// Where the bottom dock runs, and what that leaves the right hand panel.
///
/// On a document with time the panel runs the whole height of the window and
/// the timeline sits under the picture only (Next, `next-panel-full-height`;
/// the user's answer on the-panel-keeps-its-promise-on-a-video-document,
/// 2026-10-20). Before it the timeline ran under the panel as well, as
/// `video.html` draws it, and every point of its height came off the panel,
/// so Appearance and Effects were below the bottom of a laptop window with a
/// clip or a title picked. An icon's one-lap motion strip still runs under
/// both columns: a lag is a relationship between two bars, read on one ruler.
public enum PanelColumn {

    /// Whether the bottom dock sits under the picture only, leaving the panel
    /// the window's full height.
    public static func timelineUnderPictureOnly(documentHasTime: Bool, switchOn: Bool) -> Bool {
        documentHasTime && switchOn
    }

    /// The panel column's height in a window `window` points tall whose
    /// bottom dock is `timeline` points tall.
    public static func height(window: CGFloat, timeline: CGFloat, timelineUnderPanel: Bool) -> CGFloat {
        guard timelineUnderPanel else { return window }
        return max(0, window - timeline)
    }
}
