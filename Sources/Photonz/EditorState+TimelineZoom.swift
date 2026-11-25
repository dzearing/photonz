import Foundation
import QuartzCore
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

    /// Whether this timeline zooms at all: the feature is on and the strip is
    /// measuring a document that finishes. Any length of document zooms OUT,
    /// into room after its end; how far IN is `canZoomTimelineIn`.
    var canOpenOutTheTimeline: Bool {
        Experiments.shared.timelineZoomEnabled && motionStripMeasuresADocument
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
    /// window and a step either side, moving only once the window has gone
    /// a step: a whole window where the lanes' painting allows, else half
    /// (`TimelineDrawnStretch`, `timelineDrawnStepShare`).
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
    /// The ruler the painting lanes paint against: the window's own, or
    /// while a zoom holds their last painting, the window it was painted at
    /// (`timelineHeldPainting`). Laid across the lane, it is stretched by
    /// `timelinePaintStretch` to stand for the window.
    var timelinePaintRuler: MotionStripRuler {
        guard let held = timelineHeldPainting else { return motionStripRuler }
        return paintRuler(held.zoom)
    }

    /// How much wider the painting is drawn than it was painted: one unless
    /// a zoom holds it.
    var timelinePaintStretch: CGFloat {
        guard let held = timelineHeldPainting else { return 1 }
        return CGFloat(TimelinePaint.stretch(painted: paintRuler(held.zoom), to: motionStripRuler, heldForMS: 0) ?? 1)
    }

    /// How far in the painting was painted, for how strongly a clip's
    /// pictures show (`ClipPiecesBar.picturesOpacity`).
    var timelinePaintScaleOnly: TimelineZoom {
        guard let held = timelineHeldPainting else { return timelineScaleOnly }
        return TimelineZoom(scale: held.zoom.scale, startMS: 0)
    }

    /// Where the left edge could reach when the painting was painted
    /// (`timelineLeftEdgeRangeMS`).
    var timelinePaintLeftEdgeRangeMS: ClosedRange<Double> {
        timelineHeldPainting?.leftEdgeMS ?? timelineLeftEdgeRangeMS
    }

    private func paintRuler(_ zoom: TimelineZoom) -> MotionStripRuler {
        MotionStripRuler(documentMS: motionStripCycleMS, zoom: zoom.clamped(documentMS: timelineLengthForZoomMS))
    }

    /// Called as the window is written, before it changes: on a zoom, keeps
    /// the painting the lanes laid last while a stretch of it stands for the
    /// new window (`TimelinePaint.stretch`), and paints again past that; on
    /// any other move, paints at the window. A zoom a step at a time near
    /// the whole-hour view of the reference edit painted every lane again on
    /// every frame, for a change of scale of four per cent (2026-11-19).
    func holdTimelinePainting(to newValue: TimelineZoom, isZoom: Bool,
                              atRest: (stretch: ClosedRange<Double>, leftEdge: ClosedRange<Double>)? = nil) {
        if !isZoom, newValue == timelineZoom { return }
        // Nor with a hand in a lane, whose lanes are laid out against the
        // window (`noteTimelineLaneFrame`).
        guard isZoom, motionStripMeasuresADocument, canOpenOutTheTimeline, !timelineLanesHaveAHandIn else {
            letGoOfTheHeldPainting()
            return
        }
        let now = CACurrentMediaTime()
        let held = timelineHeldPainting
            ?? TimelineHeldPainting(zoom: timelineZoom, leftEdgeMS: atRest?.leftEdge ?? timelineLeftEdgeRangeMS,
                                    since: now, paintedMS: atRest?.stretch)
        guard TimelinePaint.stretch(painted: paintRuler(held.zoom), to: paintRuler(newValue),
                                    heldForMS: (now - held.since) * 1000) != nil else {
            letGoOfTheHeldPainting()
            return
        }
        if timelineHeldPainting != held { timelineHeldPainting = held }
        // Painted again a moment after the last step, once the zoom stops.
        timelineHeldPaintingSettle?.cancel()
        timelineHeldPaintingSettle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(TimelineHeldPainting.settleMS))
            guard !Task.isCancelled else { return }
            self?.letGoOfTheHeldPainting()
        }
    }

    /// Called each time the window is written: the lanes lay out against a
    /// frame that holds still while the timeline moves, and go back to the
    /// window once it has rested `TimelineHeldPainting.settleMS`
    /// (`TimelineLaneFrame`). Near the whole-hour view of the hour-long
    /// reference edit a lane laid out against the window built itself again
    /// on every frame of a zoom or a scroll (2026-11-21). Never while a hand
    /// is on something in a lane: a drag reads the window, and the edge
    /// scroll moves it under the hand.
    func noteTimelineLaneFrame() {
        guard motionStripMeasuresADocument, canOpenOutTheTimeline, !timelineEdgeScroll.isFollowing,
              !timelineLanesHaveAHandIn else {
            letGoOfTheLaneFrame()
            return
        }
        let length = timelineLengthForZoomMS
        let frame: TimelineLaneFrame
        if let held = timelineHeldPainting {
            frame = .holding(paintRuler(held.zoom), leftEdgeMS: held.leftEdgeMS,
                             zoomScale: TimelineZoom(scale: held.zoom.scale).clamped(documentMS: length).scale,
                             painted: held.paintedMS)
        } else if timelinePaintsTheWindow {
            frame = .zooming(motionStripRuler, leftEdgeMS: timelineLeftEdgeRangeMS,
                             zoomScale: timelineScaleOnly.scale)
        } else {
            let visible = timelineScaleOnly.visibleMS(documentMS: length)
            let edge = timelineDrawnStretch.leftEdgeMS(visibleMS: visible, documentMS: length)
            frame = .scrolling(motionStripRuler, anchorMS: edge.lowerBound, drawnMS: timelineDrawnMS,
                               leftEdgeMS: timelineLeftEdgeRangeMS, zoomScale: timelineScaleOnly.scale)
        }
        timelineLaneWaves.step(to: frame, window: motionStripRuler, rest: timelineRestFrame)
        showTimelineLaneWaves()
        timelineLaneFrameSettle?.cancel()
        timelineLaneFrameSettle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(TimelineHeldPainting.settleMS))
            // The lanes back on the window, a group a refresh.
            while !Task.isCancelled, let self, self.restSomeTimelineLanes() {
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
    }

    /// The lanes back on the window, all at once.
    func letGoOfTheLaneFrame() {
        timelineLaneFrameSettle?.cancel()
        timelineLaneFrameSettle = nil
        timelineLaneWaves.restAll()
        showTimelineLaneWaves()
    }

    /// The next group of lanes back on the window; false once all are. What
    /// rests paints the whole drawn stretch again, as before a zoom, so the
    /// scroll that follows one finds it painted.
    private func restSomeTimelineLanes() -> Bool {
        letTheZoomsPaintingRest()
        let more = timelineLaneWaves.restNext()
        showTimelineLaneWaves()
        return more
    }

    /// What each group stands on, where its lanes read it; and what a lane at
    /// rest is laid out from, which holds still while any lane stands on its
    /// layout at rest and the timeline moves.
    private func showTimelineLaneWaves() {
        for (group, frame) in zip(timelineLaneGroups, timelineLaneWaves.groups) where group.frame != frame {
            group.frame = frame
        }
        if timelineLaneWaves.frame == nil || !timelineLaneWaves.someRest { restTimelineWhereItIs() }
    }

    /// How a lane at rest is laid out: against the window, or while a scroll
    /// or a zoom has begun and its turn has not come, the window it rested in
    /// (`TimelineLaneWaves`). Read by the lanes in place of the window, so
    /// the first frame of a scroll or a zoom lays none of them out again.
    var timelineRestFrame: TimelineLaneFrame {
        guard motionStripMeasuresADocument else {
            let drawn = timelineDrawnMS
            return .resting(motionStripRuler, painted: drawn, drawnMS: drawn, leftEdgeMS: 0...0, zoomScale: 1)
        }
        let rest = timelineRest
        let length = timelineLengthForZoomMS
        let canZoom = canOpenOutTheTimeline
        let zoom = canZoom ? rest.zoom.clamped(documentMS: length) : .fit
        let ruler = MotionStripRuler(documentMS: motionStripCycleMS, zoom: zoom)
        let scale = canZoom ? TimelineZoom(scale: rest.zoom.scale).clamped(documentMS: length) : .fit
        let visible = scale.visibleMS(documentMS: length)
        let drawn = rest.drawnStretch.stretchMS(visibleMS: visible, documentMS: length)
        return .resting(ruler,
                        painted: TimelinePaint.paintedMS(window: ruler, stretch: drawn, isZooming: rest.paintsTheWindow),
                        drawnMS: drawn,
                        leftEdgeMS: rest.paintsTheWindow ? TimelinePaint.leftEdgeWhileZooming(window: ruler)
                            : rest.drawnStretch.leftEdgeMS(visibleMS: visible, documentMS: length),
                        zoomScale: scale.scale)
    }

    /// The frame one track's lane lays out against while the timeline moves:
    /// nil at rest, before its turn, and while a hand is on anything in a
    /// lane, which reads the window. Read only while there is a frame, so a
    /// lane at rest is not woken by every move of a drag.
    func timelineLaneFrameStanding(onTrack id: UUID) -> TimelineLaneFrame? {
        guard let frame = timelineLaneGroups[timelineLaneGroup(of: id)].frame, !timelineLanesHaveAHandIn else { return nil }
        return frame
    }

    /// Which group a track's lane goes with: dealt out in the order the lanes
    /// are built, so the ones on screen together are spread evenly.
    private func timelineLaneGroup(of id: UUID) -> Int {
        if let group = timelineLaneGroupOf[id] { return group }
        let group = timelineLaneGroupOf.count % TimelineLaneWaves.groupCount
        timelineLaneGroupOf[id] = group
        return group
    }

    /// Something in a lane in a hand, being renamed, or a carried thing over
    /// the lanes.
    private var timelineLanesHaveAHandIn: Bool {
        !clipBarInHandIDs.isEmpty || trimSession != nil || clipTransitionDrag != nil || renamingClipID != nil
            || clipTrackDrop != nil || timelineFileHover != nil || timelineTransitionHover != nil
            || partBarDrag != nil || titlePartDrag != nil || trackRangeInHand != nil || timelineGapInHand != nil
    }

    private func letGoOfTheHeldPainting() {
        timelineHeldPaintingSettle?.cancel()
        timelineHeldPaintingSettle = nil
        if timelineHeldPainting != nil { timelineHeldPainting = nil }
    }

    var timelineLeftEdgeRangeMS: ClosedRange<Double> {
        guard motionStripMeasuresADocument else { return 0...0 }
        // While a zoom paints only the window, its painting is held only
        // while the edge stays close to where it was painted, so only the
        // clips there have their names drawn against the window
        // (`TimelinePaint.leftEdgeWhileZooming`).
        if timelinePaintsTheWindow { return TimelinePaint.leftEdgeWhileZooming(window: motionStripRuler) }
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
    /// what puts the overview bar and the "1:00 to 1:30" reading up. Fit from
    /// the start is not, so the strip does not grow at Fit.
    var isTimelineOpenedOut: Bool {
        canOpenOutTheTimeline && !timelineWindow.showsAll(documentMS: timelineLengthForZoomMS)
    }

    /// Whether the window has anywhere along to go, which is what puts the
    /// scroller up and lets a scroll, a drag at the edge or the playhead move
    /// it. At Fit it has: half a window of room after the end
    /// (`TimelineZoom.roomShare`). As far out as it goes it has not.
    var canScrollTimeline: Bool {
        canOpenOutTheTimeline && timelineWindow.canScroll(documentMS: timelineLengthForZoomMS)
    }

    /// How much time the scroller spans: the document and the room after it.
    var timelineScrollableMS: Double {
        timelineWindow.scrollableMS(documentMS: timelineLengthForZoomMS)
    }

    /// Whether Fit would change anything: zoomed in, or out past the end.
    var canFitTimeline: Bool { canOpenOutTheTimeline && !timelineWindow.isFit }

    /// What the local bar says is on screen: `1:00 to 1:30`, or `all 5:00`.
    var timelineWindowReading: String {
        timelineWindow.reading(documentMS: timelineLengthForZoomMS, display: timeDisplay)
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
        guard canFitTimeline else { return }
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
        guard canScrollTimeline else { return }
        setTimelineWindow(timelineWindow.panned(byMS: delta,
                                                documentMS: timelineLengthForZoomMS))
        rememberTimelineView()
    }

    /// Slide the window under a drag held at the lanes' left or right edge
    /// (`TimelineEdgeScroll`). Remembered once, when the drag lets go, rather
    /// than sixty times a second.
    func edgePanTimeline(byMS delta: Double) {
        guard canScrollTimeline else { return }
        setTimelineWindow(timelineWindow.panned(byMS: delta,
                                                documentMS: timelineLengthForZoomMS))
    }

    /// Put the window around a moment. What clicking the overview does.
    func centreTimeline(onMS ms: Double) {
        guard canScrollTimeline else { return }
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
        guard moved, canScrollTimeline, !timelineEdgeScroll.isFollowing, timelineZoomGlide == nil else { return }
        setTimelineWindow(timelineWindow.revealing(ms: Double(documentTimeMS),
                                                   documentMS: timelineLengthForZoomMS))
    }

    /// The one write. Never writes a value it already has: the strip is redrawn
    /// off this and a playing recording would otherwise redraw it thirty times
    /// a second for nothing.
    private func setTimelineWindow(_ window: TimelineZoom) {
        endTimelineGlide()
        let landing = window.clamped(documentMS: timelineLengthForZoomMS)
        guard landing != timelineZoom else { return }
        let scaleChanged = landing.scale != timelineZoom.scale
        timelineZoom = landing
        timelineRowChores.moved()
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

// MARK: - Through a change of length (user 2026-10-28)

// "we go from one zoom level to another not gracefully; there's no transition
// but it just immediately snaps". The zoom is a share of the length, so a clip
// let go past the end, the room made for one in the air, or an undo of either
// rescaled every second on the strip in one frame (`TimelineZoomGlide`).
extension EditorState {

    /// The length the strip measures may have changed: keep the seconds on
    /// screen, or, showing the whole recording with nothing in the air, glide
    /// to the same share of the new length. Called after every edit, undo and redo (`rerender`)
    /// and whenever the room for a file in the air comes or goes.
    func noteTimelineLength() {
        let now = Double(max(1, motionStripCycleMSPastAGlide))
        guard let was = timelineZoomMeasuredMS else {
            timelineZoomMeasuredMS = now
            return
        }
        guard abs(now - was) > 0.5 else { return }
        timelineZoomMeasuredMS = now
        guard canOpenOutTheTimeline else { return }
        endTimelineGlide()
        let window = timelineZoom.clamped(documentMS: was)
        if let chosen = timelineWholeRecordingScale, timelineDropRoomMS == nil,
           let glide = TimelineZoomGlide(from: window, documentMS: was, to: now, landingScale: chosen) {
            beginTimelineGlide(glide)
        } else {
            keepingTheZoomChoice { timelineZoom = window.holdingSpan(fromDocumentMS: was, toDocumentMS: now) }
        }
    }

    /// A window the app writes for itself, which leaves what the person last
    /// chose (`timelineWholeRecordingScale`) as it was.
    private func keepingTheZoomChoice(_ write: () -> Void) {
        timelineZoomKeepsItsChoice = true
        write()
        timelineZoomKeepsItsChoice = false
    }

    private func beginTimelineGlide(_ glide: TimelineZoomGlide) {
        timelineZoomGlideHeldMS = Int(glide.heldMS.rounded())
        keepingTheZoomChoice { timelineZoom = glide.zoom(at: 0) }
        let task = Task { @MainActor [weak self] in
            // Paced by the clock, and never more than a twelfth of the way in
            // one frame: the edit that changed the length is still landing
            // (thumbnails, a waveform), and a glide timed by the clock alone
            // spent its first tenth of a second behind that work and arrived
            // most of the way there in a single frame.
            var progress = 0.0
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                progress += min((now - last) / TimelineZoomGlide.seconds, 1.0 / 12)
                last = now
                guard progress < 1 else { break }
                self.keepingTheZoomChoice { self.timelineZoom = glide.zoom(at: progress) }
            }
            guard !Task.isCancelled else { return }
            self?.endTimelineGlide()
        }
        timelineZoomGlide = (glide, task)
    }

    /// Straight to where a glide in flight was going.
    func endTimelineGlide() {
        guard let (glide, task) = timelineZoomGlide else { return }
        task.cancel()
        timelineZoomGlide = nil
        timelineZoomGlideHeldMS = nil
        timelineZoom = glide.landing
    }
}


/// The window a held painting was painted at, and where the lane's left edge
/// could reach then (`EditorState.timelineHeldPainting`).
struct TimelineHeldPainting: Equatable {
    let zoom: TimelineZoom
    let leftEdgeMS: ClosedRange<Double>
    /// When it was first held (`CACurrentMediaTime`): a quick zoom may
    /// stretch it further than a slow one (`TimelinePaint.quickHoldMS`).
    let since: CFTimeInterval
    /// What the lanes painted at rest when the hold began from lanes
    /// painting the drawn stretch: the held painting keeps it, so the first
    /// frame of the zoom is the lane at rest stretched, with nothing built
    /// or laid again (`TimelineLaneFrame.holding`, pass 23). Nil when the
    /// lanes were already painting the window, as a zoom does.
    var paintedMS: ClosedRange<Double>? = nil

    /// How long after the last step of a zoom the lanes paint again.
    static let settleMS = 30
}
