import SwiftUI

/// A piece of a view drawn in a pass of its own. Whatever the piece reads off
/// the editor is watched by this view rather than by the one holding it, so
/// when only that changes, only the piece is drawn again.
///
/// The timeline is why it exists. Every frame of a scroll along time moves the
/// window, and the lanes, the ruler and the bar's `0:01 to 0:04` have to follow
/// it. Read in the body that also builds a track's header, or the dock's whole
/// grid of tracks, each of those frames rebuilt all of that too, and a pan held
/// at an edge ran one frame in twenty late
/// (`scrolling-the-timeline-along-time-keeps-every-fr`).
struct DrawnOnItsOwn<Content: View>: View {
    @ViewBuilder let content: () -> Content

    /// Every one is on the timeline, so what it reads off the document
    /// follows an edit a pass later with the rest of the timeline
    /// (`readingALatePass`). Its content runs outside the body that holds
    /// it, where that body's late reading does not reach.
    var body: some View { readingALatePass { content() } }
}
