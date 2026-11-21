import PhotonzCore
import SwiftUI

// A busy lane laid out against a frame that holds still while the timeline
// moves, and slid and stretched to the window by one small view
// (`TimelineLaneFrame`, `EditorState.noteTimelineLaneFrame`).

extension EnvironmentValues {
    /// The frame the lane this view is in lays out against while the
    /// timeline moves, or nil when it lays out against the window. A view in
    /// a lane that places itself in time reads its ruler through
    /// `EditorState.laneRuler(_:)`, so it is laid out against the same frame
    /// as the lane round it and slid with it.
    @Entry var timelineLaneFrame: TimelineLaneFrame?
}

extension EditorState {
    /// The ruler a view inside a lane places itself in time against: its
    /// lane's frame while the timeline moves, the window otherwise.
    func laneRuler(_ frame: TimelineLaneFrame?) -> MotionStripRuler {
        frame?.ruler ?? motionStripRuler
    }

    /// A point across a lane, as its frame has it, as the window has it: what
    /// a press read in the lane's own points is, for anything that reads the
    /// window (`playheadToTimelineClick`). Read when a hand arrives.
    func windowX(ofLaneX x: CGFloat, frame: TimelineLaneFrame?, laneWidth: CGFloat) -> CGFloat {
        guard let frame else { return x }
        return frame.windowX(ofFrameX: x, window: motionStripRuler, laneWidth: laneWidth,
                             scale: hostWindow?.backingScaleFactor ?? 2)
    }

    /// The other way round: a point across the lane as the window has it, as
    /// the lane's frame has it.
    func laneX(ofWindowX x: CGFloat, frame: TimelineLaneFrame?, laneWidth: CGFloat) -> CGFloat {
        guard let frame else { return x }
        return frame.frameX(ofWindowX: x, window: motionStripRuler, laneWidth: laneWidth,
                            scale: hostWindow?.backingScaleFactor ?? 2)
    }
}

/// Slides and stretches what a lane laid out against its frame to the
/// window: the one view in the lane that reads the window on every frame of
/// a scroll or a zoom, so nothing inside it is built again for that frame.
struct TimelineLaneSlide: ViewModifier {
    @Environment(EditorState.self) private var editorState
    @Environment(\.displayScale) private var displayScale
    let frame: TimelineLaneFrame?
    let laneWidth: CGFloat

    func body(content: Content) -> some View {
        let slide = frame?.slide(to: editorState.motionStripRuler, laneWidth: laneWidth, scale: displayScale)
            ?? (stretch: 1, offset: 0)
        content
            .environment(\.timelineLaneFrame, frame)
            .scaleEffect(x: slide.stretch, y: 1, anchor: .topLeading)
            .offset(x: slide.offset)
    }
}

/// The names of painted clips that run off the lane's left edge
/// (`TimelinePaintedNames`), drawn against the window over the slid lane:
/// the window is read here, on its own, so a name is never stretched with a
/// held painting and lands exactly where the window puts its clip.
struct TimelineEdgeNames: View {
    @Environment(EditorState.self) private var editorState
    let bars: [TimelinePaintedClips.Bar]
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        TimelinePaintedNames(bars: bars, ruler: editorState.motionStripRuler, drawnMS: drawnMS,
                             laneWidth: laneWidth, laneHeight: laneHeight)
            .equatable()
    }
}

/// A quiet lane's gridlines (`TimelineGridlines`), drawn against the window
/// under a lane slid with its frame, which covers only the frame's window.
struct TimelineWindowGridlines: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineGridlines(ruler: editorState.motionStripRuler, laneWidth: laneWidth, height: height)
    }
}

/// Tells a lane each time the window moves, without the lane reading the
/// window itself: a pointer held still while the timeline moves under it is
/// over something new (`TimelineTrackRow.readPointer`).
struct TimelineWindowMoves: View {
    @Environment(EditorState.self) private var editorState
    let moved: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: editorState.motionStripRuler) { moved() }
    }
}
