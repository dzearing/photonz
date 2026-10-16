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

    /// How far in the window is, and nothing about where: what a view drawn
    /// from a moment of its own reads, so a scroll along time does not draw it
    /// again (`motionStripRuler(measuredFromMS:)`).
    var timelineScaleOnly: TimelineZoom {
        guard canOpenOutTheTimeline else { return .fit }
        return TimelineZoom(scale: timelineZoomScale).clamped(documentMS: timelineLengthForZoomMS)
    }

    /// The strip's ruler with its left hand edge on `ms`: the timeline's own
    /// scale, measured from somewhere that does not move. A clip's bar is
    /// drawn against one measured from its own start and slid along by where
    /// that start is in the window (`SlidAlongTheTimeline`), so every frame of
    /// a scroll moves the bar without drawing it again.
    func motionStripRuler(measuredFromMS ms: Double) -> MotionStripRuler {
        let cycle = motionStripCycleMS
        let ruler = motionStripMeasuresADocument
            ? MotionStripRuler(documentMS: cycle, zoom: timelineScaleOnly)
            : MotionStripRuler(cycleMS: cycle)
        return ruler.measured(fromMS: ms)
    }

    /// What a clip's bar is drawn across, in the document's milliseconds: the
    /// window and at least half a window either side, moving only once the
    /// window has gone half its width (`TimelineDrawnStretch`).
    var timelineDrawnMS: ClosedRange<Double> {
        guard motionStripMeasuresADocument else {
            let lap = MotionStripRuler(cycleMS: motionStripCycleMS)
            return lap.startMS...(lap.startMS + lap.spanMS)
        }
        let length = timelineLengthForZoomMS
        return timelineDrawnStretch.stretchMS(visibleMS: timelineScaleOnly.visibleMS(documentMS: length),
                                              documentMS: length)
    }

    /// Where the window's left hand edge is, to within half a window, read
    /// without reading the edge: a bar starting past the end of this has
    /// nothing hanging off the left of the lane to keep in sight.
    var timelineLeftEdgeRangeMS: ClosedRange<Double> {
        guard motionStripMeasuresADocument else { return 0...0 }
        let length = timelineLengthForZoomMS
        return timelineDrawnStretch.leftEdgeMS(visibleMS: timelineScaleOnly.visibleMS(documentMS: length),
                                               documentMS: length)
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

    // MARK: Moving along

    /// Slide the window, in the strip's own points. What dragging the overview
    /// does.
    func panTimeline(byMS delta: Double) {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.panned(byMS: delta,
                                                documentMS: timelineLengthForZoomMS))
        rememberTimelineView()
    }

    /// Slide the window under a drag held at the lanes' left or right edge
    /// (`TimelineEdgeScroll`). Remembered once, when the drag lets go, rather
    /// than sixty times a second.
    func edgePanTimeline(byMS delta: Double) {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.panned(byMS: delta,
                                                documentMS: timelineLengthForZoomMS))
    }

    /// Put the window around a moment. What clicking the overview does.
    func centreTimeline(onMS ms: Double) {
        guard isTimelineOpenedOut else { return }
        setTimelineWindow(timelineWindow.centred(onMS: ms,
                                                 documentMS: timelineLengthForZoomMS))
        rememberTimelineView()
    }

    /// The playhead moved, so the window follows it if it had to.
    ///
    /// Called from `documentMomentChanged`, which is every scrub and every
    /// frame of playback, so it has to be free when there is nothing to do:
    /// `revealing` hands back the same window it was given when the playhead
    /// is already on screen, and writing the same value back changes nothing.
    ///
    /// Only when the PLAYHEAD moved: an edit redraws the moment too, and a
    /// window scrolled away from a still playhead (by hand, or by a drag held
    /// at an edge, `TimelineEdgeScroll`) must not jump back to it the moment
    /// the drag lets go.
    func followTimelineWindow() {
        let moved = timelineFollowedMS != documentTimeMS
        timelineFollowedMS = documentTimeMS
        // A drag scrolling the timeline at its edge has the window; the
        // playhead does not pull it back from under the hand.
        guard moved, isTimelineOpenedOut, !timelineEdgeScroll.isFollowing else { return }
        setTimelineWindow(timelineWindow.revealing(ms: Double(documentTimeMS),
                                                   documentMS: timelineLengthForZoomMS))
    }

    /// The one write. Never writes a value it already has: the strip is redrawn
    /// off this and a playing recording would otherwise redraw it thirty times
    /// a second for nothing.
    private func setTimelineWindow(_ window: TimelineZoom) {
        let landing = window.clamped(documentMS: timelineLengthForZoomMS)
        guard landing != timelineZoom else { return }
        let scaleChanged = landing.scale != timelineZoom.scale
        timelineZoom = landing
        // Following the playhead is not a choice anybody made, so only a
        // change of scale, or a move by hand, is worth keeping for next time.
        if scaleChanged { rememberTimelineView() }
    }

    // MARK: Pinching both ways (user 2026-09-28)

    /// A pinch on the tracks: time opens out about the moment under the
    /// pointer and the rows grow about the row under it, both by the factor
    /// the fingers moved. ⌥ keeps it to time, ⇧ to the rows
    /// (`TimelinePinchAxes`).
    ///
    /// - Parameters:
    ///   - laneX: the pointer across the lanes, from their left hand edge.
    ///   - viewportY: the pointer down the tracks' view, from its top edge.
    func pinchTimeline(by factor: Double, laneX: CGFloat, laneWidth: CGFloat,
                       viewportY: CGFloat, axes: TimelinePinchAxes) {
        guard factor > 0, factor.isFinite else { return }
        if axes.zoomsTime, canOpenOutTheTimeline {
            let fraction = min(max(0, laneX / max(1, laneWidth)), 1)
            zoomTimeline(by: factor, anchorMS: motionStripRuler.ms(atFraction: Double(fraction)))
        }
        if axes.zoomsRows {
            zoomTimelineRows(by: factor, viewportY: viewportY)
        }
    }

    // MARK: Steered by the fingers (user 2026-09-28)

    /// The fingers on the trackpad, in its points: two of them, spreading one
    /// way or another, pick what a pinch zooms (`TimelinePinchSteer`).
    func timelinePinchTouched(_ points: [CGPoint]) {
        timelinePinchSteer.touched(points)
    }

    /// A pinch on the tracks begins.
    func beginTimelinePinch() {
        timelinePinchSteer.begin()
    }

    /// One nudge of a pinch on the tracks: side to side zooms time, up and
    /// down the rows, on the slant both, and ⌥ or ⇧ (`forced`) still insist.
    /// Its first nudges wait until the fingers have said which way, and go
    /// through together then. Returns what it zoomed, or nil while it waits.
    @discardableResult
    func steerTimelinePinch(by factor: Double, laneX: CGFloat, laneWidth: CGFloat,
                            viewportY: CGFloat, forced: TimelinePinchAxes?) -> TimelinePinchAxes? {
        guard let step = timelinePinchSteer.magnified(by: factor, forced: forced) else { return nil }
        pinchTimeline(by: step.factor, laneX: laneX, laneWidth: laneWidth, viewportY: viewportY,
                      axes: step.axes)
        return step.axes
    }

    /// The fingers lift: a pinch too small to have picked a way still zooms
    /// by what it moved.
    @discardableResult
    func endTimelinePinch(laneX: CGFloat, laneWidth: CGFloat, viewportY: CGFloat) -> TimelinePinchAxes? {
        guard let step = timelinePinchSteer.end() else { return nil }
        pinchTimeline(by: step.factor, laneX: laneX, laneWidth: laneWidth, viewportY: viewportY,
                      axes: step.axes)
        return step.axes
    }

    /// The rows grown (or shrunk) by a factor, keeping the spot under the
    /// pointer where it is: the same row, the same share of it.
    func zoomTimelineRows(by factor: Double, viewportY: CGFloat) {
        let landing = timelineRowZoom.zoomed(by: factor)
        guard landing != timelineRowZoom else { return }
        setTimelineRows(landing, viewportY: viewportY)
    }

    /// Back to the mock's compact rows.
    func resetTimelineRows() {
        guard !timelineRowZoom.isCompact else { return }
        setTimelineRows(.compact, viewportY: 0)
    }

    private func setTimelineRows(_ landing: TimelineRowZoom, viewportY: CGFloat) {
        let geometry = timelineTracksScrollGeometry
        let before = TimelineDock.rowExtents(of: self, rows: timelineRowZoom)
        let after = TimelineDock.rowExtents(of: self, rows: landing)
        let contentAfter = (after.last?.bottom ?? 0) + TimelineDock.rowSpacing
        let offset = TimelineRowZoom.offset(keepingViewportY: viewportY, offset: geometry.offsetY,
                                            from: before, to: after, contentHeight: contentAfter,
                                            viewportHeight: geometry.viewportHeight)
        timelineRowZoom = landing
        // The scroll moves in the same breath as the rows, so no frame is ever
        // drawn with the new rows at the old scroll.
        timelineTracksScroll.scrollTo(y: offset)
        timelineTracksScrollGeometry.offsetY = offset
        timelineTracksScrollGeometry.contentHeight = contentAfter
        rememberTimelineView()
    }

    /// The track the picked layer is on: where its row stands among the
    /// timeline's rows, how tall it is with what is open inside it, and how
    /// tall with nothing open. Both at compact rows, so a pinch growing the
    /// rows never reads as a pick opening one and scrolls the timeline out
    /// from under the pointer (timeline-pinch-both-ways-walk, 2026-10-16).
    /// Nil with nothing picked on the timeline.
    var pickedTimelineRow: PickedTimelineRow? {
        guard let picked = selectedLayerID else { return nil }
        for (index, row) in timelineRows.enumerated() {
            guard case .track(let track, _) = row,
                  track.clips.contains(where: { $0.layerID == picked })
                    || track.inner.contains(where: { $0.layerID == picked }) else { continue }
            let open = isKeyTrackOpen(track.track.id)
            return PickedTimelineRow(trackID: track.track.id, index: index,
                                     height: TimelineDock.height(of: track, wordsOpen: open),
                                     ownHeight: TimelineDock.ownHeight(of: track, wordsOpen: open))
        }
        return nil
    }

    /// A pick or a key has just opened rows inside the picked layer's track:
    /// note it, so the timeline scrolls them on screen once they are laid out
    /// (`revealOpenedTimelineRow`). A pick that opens nothing, or a row that
    /// only shrank, leaves the scroll where the person put it.
    func notePickedTimelineRow(_ row: PickedTimelineRow?, after before: PickedTimelineRow?) {
        timelineRowToReveal = nil
        guard let row else { return }
        let sameTrack = before?.trackID == row.trackID
        let opened = sameTrack ? row.height > (before?.height ?? 0) + 0.5 : row.height > row.ownHeight + 0.5
        guard opened else { return }
        timelineRowToReveal = TimelineRowToReveal(trackID: row.trackID,
                                                  heightBefore: sameTrack ? trackRowDrag.rowFrames[row.trackID]?.height : nil)
    }

    /// A track's row laid out at `frame`, in the tracks' own space: if it is
    /// the one a pick or a key just opened rows in, the timeline scrolls the
    /// least that shows what opened (`TimelineRowReveal`). Measured rather
    /// than worked out, because an open graph is taller than its lane.
    func revealOpenedTimelineRow(_ id: UUID, at frame: CGRect) {
        guard let pending = timelineRowToReveal, pending.trackID == id else { return }
        if let before = pending.heightBefore, frame.height <= before + 0.5 { return }
        timelineRowToReveal = nil
        // The same track grown: what it grew by, which a new lane opens at its
        // foot. A track newly picked: the whole of it.
        var target = TimelineRowExtent(top: frame.minY, height: frame.height)
        if let before = pending.heightBefore {
            target = TimelineRowExtent(top: frame.maxY - (frame.height - before), height: frame.height - before)
        }
        let geometry = timelineTracksScrollGeometry
        let contentHeight = max(geometry.contentHeight, target.bottom + TimelineDock.rowSpacing)
        guard let landing = TimelineRowReveal.offset(revealing: target, offset: geometry.offsetY,
                                                     viewportHeight: geometry.viewportHeight,
                                                     contentHeight: contentHeight) else { return }
        timelineTracksScroll.scrollTo(y: landing)
    }

    /// The tracks scrolled by hand, from their scroller.
    func scrollTimelineTracks(toY y: CGFloat) {
        let geometry = timelineTracksScrollGeometry
        let landing = min(max(0, y), max(0, geometry.contentHeight - geometry.viewportHeight))
        timelineTracksScroll.scrollTo(y: landing)
    }

    // MARK: Kept per file

    static let timelineViewMemoryKey = "timeline.viewMemory"

    /// Where this window's timeline is filed: the recording or project it is
    /// editing. Nil for something never saved, which has nothing to come back
    /// to.
    private var timelineViewMemoryFile: String? {
        (documentURL ?? recordingURL ?? openedFileURL)?.standardizedFileURL.path
    }

    private static func loadTimelineViewMemory() -> TimelineViewMemory {
        guard let data = UserDefaults.standard.data(forKey: timelineViewMemoryKey),
              let memory = try? JSONDecoder().decode(TimelineViewMemory.self, from: data)
        else { return TimelineViewMemory() }
        return memory
    }

    /// Files away how the timeline is being looked at, once a pinch has
    /// settled: a pinch is sixty changes a second, and none but the last is
    /// worth a write.
    func rememberTimelineView() {
        guard documentHasTime, let file = timelineViewMemoryFile else { return }
        timelineViewMemoryWrite?.cancel()
        timelineViewMemoryWrite = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            var memory = Self.loadTimelineViewMemory()
            let before = memory
            memory.remember(zoom: self.timelineWindow, rows: self.timelineRowZoom, for: file)
            guard memory != before, let data = try? JSONEncoder().encode(memory) else { return }
            UserDefaults.standard.set(data, forKey: Self.timelineViewMemoryKey)
        }
    }

    /// The timeline as it was left last time this file was open. Called once
    /// the file the window holds is known.
    func restoreTimelineView() {
        guard documentHasTime, let file = timelineViewMemoryFile,
              let kept = Self.loadTimelineViewMemory().recall(for: file) else { return }
        timelineRowZoom = kept.rows
        if canOpenOutTheTimeline {
            timelineZoom = kept.zoom.clamped(documentMS: timelineLengthForZoomMS)
        }
    }

    /// What a walk reads to know how tall the rows are.
    var timelineRowsReading: String {
        String(format: "rows %.2fx", timelineRowZoom.scale)
    }
}

/// How the tracks' scroll stands: how far down, how tall the tracks are, and
/// how tall the view onto them is.
struct TimelineTracksScrollGeometry: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    /// There is more than fits, so the scroller has something to say.
    var overflows: Bool { contentHeight > viewportHeight + 0.5 }
}

/// The picked layer's track on the timeline (`EditorState.pickedTimelineRow`).
struct PickedTimelineRow: Equatable {
    let trackID: UUID
    let index: Int
    let height: CGFloat
    let ownHeight: CGFloat
}

/// A track a pick or a key just opened rows in, waiting to be laid out so the
/// timeline can scroll them on screen. `heightBefore` is its row's height
/// before they opened, nil when it is newly picked.
struct TimelineRowToReveal: Equatable {
    let trackID: UUID
    let heightBefore: CGFloat?
}
