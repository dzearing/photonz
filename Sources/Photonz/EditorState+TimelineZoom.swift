import Foundation
import PhotonzCore

// **Opening the timeline out** (`TimelineZoom.swift`,
// `docs/design/video-surface.md`).
//
// A thin layer over the arithmetic in `PhotonzCore`, exactly like the rest of
// the strip. Everything here answers one of three questions: what stretch of
// the document is on screen, how the window moves, and what the local bar says
// about it.
//
// The zoom is NOT in the document. How far you have opened the timeline out is
// how you are looking at a recording, not part of it: it does not belong in a
// file, it is not an undo step, and two windows on the same document are
// allowed to be looking at different seconds of it.
extension EditorState {

    /// How long the thing the strip is measuring is, in the strip's own terms.
    /// The lap for an icon, the document for a recording, and the length HELD
    /// through a drag either way, so the window can never rescale under a hand
    /// (`motionStripCycleMS`).
    var timelineLengthForZoomMS: Double { Double(max(1, motionStripCycleMS)) }

    /// Whether this timeline can be opened out at all: the feature is on, the
    /// strip is measuring a document that finishes, and the document is long
    /// enough that there is something to open out into.
    var canOpenOutTheTimeline: Bool {
        Experiments.shared.timelineZoomEnabled
            && motionStripMeasuresADocument
            && TimelineZoom.widestScale(documentMS: timelineLengthForZoomMS) > 1
    }

    /// The window on the document, always inside it. Read by the ruler, so
    /// nothing else has to remember to clamp.
    var timelineWindow: TimelineZoom {
        guard canOpenOutTheTimeline else { return .fit }
        return timelineZoom.clamped(documentMS: timelineLengthForZoomMS)
    }

    /// The moment a zoom happens ABOUT: the playhead where it is on screen,
    /// and the middle of the window where it is not.
    ///
    /// The playhead is what you are working on, so keeping it still under a
    /// zoom is what makes the control usable at all. When it is somewhere else
    /// entirely, holding it still would throw away the stretch you were
    /// looking at to chase a playhead you cannot see.
    var timelineZoomAnchorMS: Double {
        let window = timelineWindow
        let playhead = Double(documentTimeMS)
        if window.contains(ms: playhead, documentMS: timelineLengthForZoomMS) { return playhead }
        return window.startMS + window.visibleMS(documentMS: timelineLengthForZoomMS) / 2
    }

    var canZoomTimelineIn: Bool {
        canOpenOutTheTimeline && timelineWindow.canZoomIn(documentMS: timelineLengthForZoomMS)
    }

    var canZoomTimelineOut: Bool { canOpenOutTheTimeline && timelineWindow.canZoomOut }

    /// Whether the strip is showing less than the whole document, which is
    /// what puts the overview bar up.
    var isTimelineOpenedOut: Bool { canOpenOutTheTimeline && !timelineWindow.isFit }

    /// What the local bar says is on screen: `1:00 to 1:30`, or `all 5:00`.
    var timelineWindowReading: String {
        timelineWindow.reading(documentMS: timelineLengthForZoomMS)
    }

    // MARK: Moving in and out

    func zoomTimelineIn() {
        guard canZoomTimelineIn else { return }
        setTimelineWindow(timelineWindow.steppedIn(anchorMS: timelineZoomAnchorMS,
                                                   documentMS: timelineLengthForZoomMS))
    }

    func zoomTimelineOut() {
        guard canZoomTimelineOut else { return }
        setTimelineWindow(timelineWindow.steppedOut(anchorMS: timelineZoomAnchorMS,
                                                    documentMS: timelineLengthForZoomMS))
    }

    /// The whole document back across the width. One press, from however far
    /// in: the way back out is never a sequence of presses.
    func fitTimeline() {
        guard canOpenOutTheTimeline else { return }
        setTimelineWindow(.fit)
    }

    /// A pinch on the strip. The scale is multiplied rather than stepped, so
    /// the timeline follows the fingers instead of jumping a notch at a time.
    func zoomTimeline(by factor: Double, anchorMS: Double) {
        guard canOpenOutTheTimeline, factor > 0 else { return }
        setTimelineWindow(timelineWindow.zoomed(toScale: timelineWindow.scale * factor,
                                                anchorMS: anchorMS,
                                                documentMS: timelineLengthForZoomMS))
    }

    /// The zoom steps on the timeline's own bar (`video.html` `#zoomSeg`):
    /// Fit and then doubling, each one there only while the document is long
    /// enough to open out that far.
    var timelineZoomSteps: [Double] {
        guard canOpenOutTheTimeline else { return [] }
        let widest = TimelineZoom.widestScale(documentMS: timelineLengthForZoomMS)
        return [1, 2, 4, 8].filter { $0 <= widest + 0.0001 }
    }

    /// Straight to one of those steps, about the same moment a press on the
    /// zoom in button would keep still.
    func setTimelineScale(_ scale: Double) {
        guard canOpenOutTheTimeline else { return }
        if scale <= 1 { return fitTimeline() }
        setTimelineWindow(timelineWindow.zoomed(toScale: scale, anchorMS: timelineZoomAnchorMS,
                                                documentMS: timelineLengthForZoomMS))
    }

    // MARK: Moving along

    /// Slide the window, in the strip's own points. What dragging the overview
    /// does.
    func panTimeline(byMS delta: Double) {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.panned(byMS: delta,
                                                documentMS: timelineLengthForZoomMS))
    }

    /// Put the window around a moment. What clicking the overview does.
    func centreTimeline(onMS ms: Double) {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.centred(onMS: ms,
                                                 documentMS: timelineLengthForZoomMS))
    }

    /// The playhead moved, so the window follows it if it had to.
    ///
    /// Called from `documentMomentChanged`, which is every scrub and every
    /// frame of playback, so it has to be free when there is nothing to do:
    /// `revealing` hands back the same window it was given when the playhead
    /// is already on screen, and writing the same value back changes nothing.
    func followTimelineWindow() {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.revealing(ms: Double(documentTimeMS),
                                                   documentMS: timelineLengthForZoomMS))
    }

    /// The one write. Never writes a value it already has: the strip is redrawn
    /// off this and a playing recording would otherwise redraw it thirty times
    /// a second for nothing.
    private func setTimelineWindow(_ window: TimelineZoom) {
        let landing = window.clamped(documentMS: timelineLengthForZoomMS)
        guard landing != timelineZoom else { return }
        timelineZoom = landing
    }
}
