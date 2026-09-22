import AppKit
import Foundation
import PhotonzCore

/// The timing strip across the bottom of the window (`next-motion-strip`,
/// `MotionStrip.swift`).
///
/// Everything here is a thin layer over the pure arithmetic in `PhotonzCore`.
/// The strip reads the WHOLE document rather than the picked layer, which is
/// the whole reason it exists: the Motion list in the side column speaks for
/// one layer, and a lag is a relationship between two.
extension EditorState {

    // MARK: Whether there is a strip at all

    /// True where this document has something moving in it and the feature is
    /// switched on. A still document has no strip, not an empty one: a bar of
    /// chrome saying "nothing here" costs canvas and tells you what you already
    /// know by looking at the picture.
    var hasMotionStrip: Bool {
        guard let document else { return false }
        // Two jobs, one strip, and two different switches. A document with a
        // duration has a row per clip whether or not anything on it is
        // animated, so its timeline is part of cutting a recording and cannot
        // depend on the Motion list existing — a video with the Motion flag off
        // would otherwise lose its timeline and with it the document
        // (`docs/design/video-surface.md` §2, §6).
        if document.hasTime { return Experiments.shared.cutRecordingEnabled }
        return Experiments.shared.motionStripEnabled && document.hasMotion
    }

    /// Whether it is on screen right now: there is one, and it has not been
    /// put away.
    var isMotionStripShown: Bool { hasMotionStrip && isMotionStripOpen }

    /// The lanes, grouped under the layer each belongs to.
    var motionStripGroups: [MotionStripGroup] {
        // The document AS SHOWN: while a trim runs the clip is laid out at
        // full length, so its bar covers everything the trim could give back
        // and the handles bracket the part being kept (`EditorState+Trim`).
        guard let document = shownDocument else { return [] }
        var groups = document.motionStrip()
        // A bar under the hand is drawn where the hand has it, not where the
        // document still says it is, which is the same bargain the pivot
        // crosshair and the lens slider strike.
        if let drag = motionTimingDrag {
            for group in groups.indices {
                for lane in groups[group].lanes.indices
                where groups[group].lanes[lane].motionID == drag.motionID {
                    // The hand works in the DOCUMENT's clock, which is what the
                    // lanes are drawn in, so the landing goes straight on. The
                    // marks on the bar travel with it in proportion, the same
                    // way the stops under them will when the drag is written
                    // down (`MotionStripLane.retimed(to:)`).
                    groups[group].lanes[lane] = groups[group].lanes[lane].retimed(to: drag.timing)
                }
            }
        }
        // ...and a KEY under the hand is drawn where the hand has it, while
        // everything else on its bar stays exactly where it was.
        if let drag = motionStopDrag {
            for group in groups.indices {
                for lane in groups[group].lanes.indices
                where groups[group].lanes[lane].motionID == drag.motionID
                    && groups[group].lanes[lane].keys.indices.contains(drag.middle) {
                    groups[group].lanes[lane].keys[drag.middle].ms = drag.atMS
                }
            }
        }
        return groups
    }

    /// How long one lap is, as the strip is drawing it.
    ///
    /// While a bar is being dragged this is the length the lap had when it was
    /// GRABBED. A lap that grew to fit the bar being dragged would rescale the
    /// ruler under the hand doing the dragging, and the bar would chase the
    /// pointer instead of following it.
    var motionStripCycleMS: Int {
        if let drag = motionTimingDrag { return drag.heldCycleMS }
        // ...and the same for a CLIP's bar, for the same reason
        // (`EditorState+ClipBar`).
        if let drag = clipBarDrag { return drag.heldTimelineMS }
        return max(1, shownDocument?.timelineLengthMS ?? 1)
    }

    /// Whether this document finishes rather than repeating. A recording has a
    /// last frame; an icon starts over.
    var motionStripMeasuresADocument: Bool { document?.hasTime ?? false }

    /// The ruler the strip is drawn against.
    ///
    /// Two rulers, and they are not interchangeable. A lap leaves a third of
    /// itself spare past the end so a bar that overruns the restart has
    /// somewhere to be drawn. A document has a last frame, so its ruler ends
    /// where the picture does and there is no restart to mark.
    ///
    /// A document's ruler measures the WINDOW, which is the whole of the zoom:
    /// everything on the strip is laid out through this one ruler, so opening
    /// the timeline out is the ruler covering less time and nothing else
    /// (`EditorState+TimelineZoom`).
    var motionStripRuler: MotionStripRuler {
        motionStripMeasuresADocument
            ? MotionStripRuler(documentMS: motionStripCycleMS, zoom: timelineWindow)
            : MotionStripRuler(cycleMS: motionStripCycleMS)
    }

    /// Whether the lap simply follows the longest motion.
    var motionCycleIsAutomatic: Bool { document?.motionCycleIsAutomatic ?? true }

    /// True where the strip has been put away and the row it left behind is
    /// on screen in its place.
    ///
    /// A document with nothing moving has neither, which is the same rule the
    /// strip itself follows: a row saying "nothing is moving" is a row telling
    /// you what the picture already told you.
    var isMotionStripCollapsed: Bool { hasMotionStrip && !isMotionStripOpen }

    /// Which of the three states the bottom of the window is in. One value so
    /// the view has one switch and the animation has one thing to watch.
    var motionStripPhase: MotionStripPhase {
        guard hasMotionStrip else { return .none }
        return isMotionStripOpen ? .open : .row
    }

    /// What the row says while the strip is away: the layer you are working
    /// on, what is moving on it, and how long a lap is
    /// (`MotionStripSummary`).
    var motionStripSummary: String {
        MotionStripSummary.text(groups: motionStripGroups,
                                selectedLayerID: selectedLayerID,
                                cycleMS: motionStripCycleMS)
    }

    // MARK: Putting it away and bringing it back

    /// The × on the strip and the row it leaves behind are the same one
    /// switch, and so is ⌥⌘T. Putting it away is remembered, which it can
    /// safely be now that away means a row rather than nothing: the strip can
    /// no longer come back to a document that gives no sign it exists.
    func toggleMotionStrip() { isMotionStripOpen.toggle() }

    // MARK: How long one lap is

    /// The lap length typed into the strip's own readout. One undo step, like
    /// every other number in the app.
    func setMotionCycleMS(_ ms: Int) {
        guard document?.motionCycleMS != max(1, ms) else { return }
        perform { $0.motionCycleMS = max(1, ms) }
        motionChanged()
    }

    /// Back to following the longest motion.
    func clearMotionCycle() {
        guard document?.motionCycleMS != nil else { return }
        perform { $0.motionCycleMS = nil }
        motionChanged()
    }

    // MARK: Dragging a bar

    /// A bar taken hold of.
    ///
    /// The lap length is held for the length of the drag and the timing is
    /// worked out from where the bar was when it was grabbed, so neither the
    /// ruler nor the bar can creep while the hand is moving.
    func beginMotionTimingDrag(motionID: UUID, grab: MotionStripDrag.Grab) {
        guard let document,
              let lane = document.motionStrip().flatMap(\.lanes).first(where: { $0.motionID == motionID })
        else { return }
        // Picking the bar picks its layer, so the numbers in the side column
        // are the numbers of the bar in your hand. Without this you would be
        // dragging one thing and reading another.
        if selectedLayerID != lane.layerID { selectLayer(lane.layerID) }
        // The same thing grabbing the pivot does, for the same reason: a lag
        // cannot be judged on a still picture, and the hand about to move this
        // bar is asking what it looks like (`motionGestureBegan`).
        motionGestureBegan()
        motionTimingDrag = MotionTimingDrag(
            motionID: motionID,
            layerID: lane.layerID,
            grab: MotionStripDrag(grab: grab, timing: lane.timing,
                                  others: document.motionStripEdges(excluding: motionID),
                                  snapWithinMS: Self.motionSnapMS(cycleMS: document.motionCycleLengthMS)),
            timing: lane.timing,
            heldCycleMS: max(1, document.motionCycleLengthMS),
            snappedTo: nil,
            gap: nil)
        watchForMotionTimingEscape()
    }

    /// Escape, for as long as there is a bar in hand.
    ///
    /// A key WATCH rather than a key binding, for the reason the dock's
    /// carried section has one: the strip never holds the keyboard during a
    /// drag — whatever had it before still does — and SwiftUI hands a gesture
    /// no key events at all, so a bar taken hold of could only be let go of by
    /// finishing the drag and undoing it.
    private func watchForMotionTimingEscape() {
        guard motionTimingEscapeWatch == nil else { return }
        motionTimingEscapeWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self,
                  motionTimingDrag != nil || motionStopDrag != nil else { return event }
            cancelMotionTimingDrag()
            cancelMotionStopDrag()
            // Swallowed: the press called this drag off and must not go on to
            // clear the selection behind it.
            return nil
        }
    }

    private func stopWatchingForMotionTimingEscape() {
        guard let watch = motionTimingEscapeWatch else { return }
        NSEvent.removeMonitor(watch)
        motionTimingEscapeWatch = nil
    }

    /// The hand moved. Nothing is written to the document: the strip and the
    /// side column both read the preview, so the numbers follow at once and the
    /// whole drag is still one step to undo.
    func updateMotionTimingDrag(byMS delta: Int) {
        guard var drag = motionTimingDrag else { return }
        let landing = drag.grab.landing(byMS: delta)
        drag.timing = landing.timing
        drag.snappedTo = landing.snappedTo
        // The lag, drawn as itself: how far this bar starts from the nearest
        // end of any other, with that other one named.
        drag.gap = MotionStripGap(startMS: landing.timing.startMS,
                                  others: drag.grab.others.filter { $0.name != MotionStripCopy.topOfTheLap })
        motionTimingDrag = drag
        // The preview keeps RUNNING while the bar moves. The canvas is handed
        // the timing under the hand rather than the one written down
        // (`displayDocument`), so the lag you are making plays as you make it,
        // which is the only way to judge whether ninety milliseconds is the
        // right ninety milliseconds.
        rerender()
    }

    /// Let go: one step for undo covering the whole drag.
    func commitMotionTimingDrag() {
        stopWatchingForMotionTimingEscape()
        guard let drag = motionTimingDrag else { return }
        motionTimingDrag = nil
        guard drag.timing != drag.grab.timing else {
            rerender()
            return
        }
        let held = drag.heldCycleMS
        perform { document in
            document.updateLayer(id: drag.layerID) { layer in
                guard var motions = layer.motions,
                      let index = motions.firstIndex(where: { $0.id == drag.motionID }) else { return }
                // ...and back into the LAYER's own clock to be written down,
                // because that is the clock a motion is stored in and the one
                // that keeps it nailed to its frame through a trim
                // (`Layer.motionShiftMS`).
                motions[index] = motions[index].retimed(to: drag.timing
                    .shifted(byMS: -layer.motionShiftMS))
                layer.motions = motions
            }
            // What the drag did to the LAP, in the same step, so undo takes
            // both back together. The rule itself is in `MotionStripCycle`,
            // where it is tested.
            document.motionCycleMS = MotionStripCycle.after(
                drag: held, automatic: document.automaticMotionCycleLengthMS,
                current: document.motionCycleMS)
        }
        // The change has landed, so the lap starts over with the new lag in it.
        motionChanged()
    }

    /// Escape, or a drag that went nowhere.
    func cancelMotionTimingDrag() {
        stopWatchingForMotionTimingEscape()
        guard motionTimingDrag != nil else { return }
        motionTimingDrag = nil
        rerender()
    }

    // MARK: Dragging one key along a bar

    /// A mark on a bar taken hold of.
    ///
    /// The other half of the same surface, and deliberately the opposite
    /// bargain to dragging the bar: **the move stays where it is and one of its
    /// moments changes.** On a punch in that pushes in, holds and pulls back
    /// out, that is the difference between starting the whole thing a second
    /// later and sitting there a second longer before pulling out.
    ///
    /// `middle` counts the keys BETWEEN the bar's two ends, from nought at the
    /// left. The ends themselves are the bar's own handles.
    func beginMotionStopDrag(motionID: UUID, key middle: Int) {
        guard let document,
              let lane = document.motionStrip().flatMap(\.lanes)
                  .first(where: { $0.motionID == motionID }),
              let grab = MotionStopDrag(
                  keys: [lane.timing.startMS] + lane.keys.map(\.ms) + [lane.timing.endMS],
                  middle: middle)
        else { return }
        // Taking hold of a mark picks its layer, so the row in the side column
        // is the row the mark belongs to.
        if selectedLayerID != lane.layerID { selectLayer(lane.layerID) }
        // The preview keeps running while the key moves, for the reason a bar
        // drag does: a hold is a length of time and it cannot be judged on a
        // still picture.
        motionGestureBegan()
        motionStopDrag = MotionStopDragState(
            motionID: motionID,
            layerID: lane.layerID,
            middle: middle,
            grab: grab,
            atMS: grab.heldMS,
            shiftMS: document.layer(id: lane.layerID)?.motionShiftMS ?? 0)
        watchForMotionTimingEscape()
    }

    /// The hand moved. Nothing is written down: the strip and the canvas both
    /// read the drag, so the whole thing stays one step to undo.
    func updateMotionStopDrag(byMS delta: Int) {
        guard var drag = motionStopDrag else { return }
        drag.atMS = drag.grab.moved(byMS: delta)
        motionStopDrag = drag
        rerender()
    }

    /// Let go: one step for undo covering the whole drag.
    func commitMotionStopDrag() {
        stopWatchingForMotionTimingEscape()
        guard let drag = motionStopDrag else { return }
        motionStopDrag = nil
        guard drag.atMS != drag.grab.heldMS else {
            rerender()
            return
        }
        perform { document in
            document.updateLayer(id: drag.layerID) { layer in
                guard var motions = layer.motions,
                      let index = motions.firstIndex(where: { $0.id == drag.motionID }) else { return }
                // ...back into the LAYER's own clock to be written down, the
                // same conversion a bar drag makes (`Layer.motionShiftMS`).
                motions[index] = motions[index].movingKey(drag.middle, toMS: drag.atMS - drag.shiftMS)
                layer.motions = motions
            }
        }
        motionChanged()
    }

    /// Escape, or a drag that went nowhere.
    func cancelMotionStopDrag() {
        stopWatchingForMotionTimingEscape()
        guard motionStopDrag != nil else { return }
        motionStopDrag = nil
        rerender()
    }

    /// What the mark under the hand says while it is moving: the moment it is
    /// at, in the units the ruler under it is written in.
    var motionStopDragReading: String? {
        guard let drag = motionStopDrag else { return nil }
        return motionStripRuler.reading(ofMS: drag.atMS)
    }

    /// How near a drop has to land to catch on another bar's end, in
    /// milliseconds. Deliberately tiny — a fortieth of the lap, so about
    /// twenty milliseconds on a nine hundred millisecond loop — because the job
    /// this strip exists for is putting one bar ninety milliseconds behind
    /// another, and a snap wide enough to be helpful for lining things up would
    /// swallow exactly that.
    static func motionSnapMS(cycleMS: Int) -> Int { max(2, cycleMS / 40) }

    // MARK: What a bar under the hand does to the picture

    /// `document` with the bar being dragged written into it, held lap and all.
    ///
    /// Read by the canvas and by the previews strip, so both play the timing
    /// the HAND has rather than the one still written down: dragging a bar
    /// while the preview runs would otherwise show you the lag you had before
    /// you started moving it, at every size at once.
    func withDraggedMotionTiming(_ document: PhotonzDocument) -> PhotonzDocument {
        var document = document
        // A KEY under the hand, so the hold you are lengthening plays at the
        // length you are giving it rather than the one written down.
        if let key = motionStopDrag {
            document.updateLayer(id: key.layerID) { layer in
                guard var motions = layer.motions,
                      let index = motions.firstIndex(where: { $0.id == key.motionID }) else { return }
                motions[index] = motions[index].movingKey(key.middle, toMS: key.atMS - key.shiftMS)
                layer.motions = motions
            }
        }
        guard Experiments.shared.motionStripEnabled, let drag = motionTimingDrag else { return document }
        document.updateLayer(id: drag.layerID) { layer in
            guard var motions = layer.motions,
                  let index = motions.firstIndex(where: { $0.id == drag.motionID }) else { return }
            motions[index] = motions[index].retimed(to: drag.timing)
            layer.motions = motions
        }
        document.motionCycleMS = drag.heldCycleMS
        return document
    }

    // MARK: What the side column reads while a bar is dragged

    /// The timing to show for this motion: the one under the hand where there
    /// is a hand on it, and the one in the document otherwise.
    ///
    /// The Start and Over fields in the side column go through here, which is
    /// the whole of "one model, two views": drag the bar and the numbers move
    /// with it, type in the numbers and the bar moves with them.
    func motionTiming(of motion: LayerMotion) -> MotionTiming {
        if let drag = motionTimingDrag, drag.motionID == motion.id { return drag.timing }
        return motion.timing
    }
}

/// A bar under a hand: what it was when it was grabbed, what it is now, and
/// what it caught on to get there.
///
/// Kept out of the document for the reason the pivot drag is: the whole drag
/// has to be one step to undo rather than forty.
struct MotionTimingDrag {
    let motionID: UUID
    let layerID: UUID
    /// The arithmetic, holding the timing the bar had when it was taken hold
    /// of and the ends of every other bar it can catch on.
    let grab: MotionStripDrag
    var timing: MotionTiming
    /// How long the lap was when the drag started, held for its length so the
    /// ruler cannot rescale under the hand.
    let heldCycleMS: Int
    var snappedTo: MotionStripEdge?
    var gap: MotionStripGap?
}

/// A key on a bar under a hand: which one, where it started, and where the
/// hand has it now.
///
/// Kept out of the document for the reason the bar drag is: the whole drag has
/// to be one step to undo rather than forty.
struct MotionStopDragState {
    let motionID: UUID
    let layerID: UUID
    /// Which of the keys between the bar's two ends, from nought at the left.
    let middle: Int
    /// The arithmetic, holding every key's moment as it was when the mark was
    /// taken hold of.
    let grab: MotionStopDrag
    /// Where the key is now, on the document's clock.
    var atMS: Int
    /// How far this layer's own clock sits along the document's, so the moment
    /// under the hand can be written back in the clock a motion is stored in.
    let shiftMS: Int
}

/// What the bottom of the window is showing: nothing, the row a put-away strip
/// leaves behind, or the strip itself.
enum MotionStripPhase: Equatable {
    case none, row, open
}
