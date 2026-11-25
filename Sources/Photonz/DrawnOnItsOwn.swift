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
    @Environment(\.timelineRowSleep) private var sleep
    @State private var kept = KeptBuild()

    /// Every one is on the timeline, so what it reads off the document
    /// follows an edit a pass later with the rest of the timeline
    /// (`readingALatePass`). Its content runs outside the body that holds
    /// it, where that body's late reading does not reach.
    var body: some View { keptAsleep(sleep, kept) { readingALatePass { content() } } }
}

/// Something laid over a slot of a known size, rather than stacked in it.
///
/// What is stacked is asked its size whenever it changes, and the answer moves
/// everything stacked after it: the ruler changing on every frame of a scroll
/// along time had SwiftUI check where each of a tall edit's fifty rows goes,
/// and everything in them, to find that none had moved. What is laid over a
/// slot has no say in its size, so nothing past it is checked.
struct TimelineSlot<Content: View>: View {
    let width: CGFloat?
    let height: CGFloat
    let content: Content

    /// Built here, in the body that holds it, so what it reads is watched
    /// there, with that body's late reading, and not by the slot.
    init(width: CGFloat? = nil, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) { content }
    }
}
