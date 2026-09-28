import AppKit
import Foundation
import PhotonzCore

// A box over the tracks, and a range on just the tracks it crosses
// (`TrackRange.swift`).
//
// A drag that starts in empty timeline space draws a box, the way Final Cut and
// Premiere draw one: every clip it touches, on the tracks it crosses, is picked
// when the hand comes up. Whole clips join the layers picked, so a drag or ⌫
// carries them as it carries any clips picked with Shift; a box over part of a
// cut recording picks just the pieces it touched.
//
// Hold ⌥ for the same drag, or take the Range tool (R), and it picks a stretch
// of time on the tracks it crosses instead, drawn over those tracks alone.
// ⌫ lifts it, ⇧⌫ (and ⌥⌫) takes it out and closes the gap on those tracks,
// ⌘T puts the default transition on every cut inside it, and every other
// track is left exactly as it was.
//
// A click on empty space moves the playhead there and lets go of what was
// picked, the way a click beside the clips does in both editors.

extension EditorState {

    /// What one press on empty track space is doing.
    struct LanePress {
        let atMS: Int
        let atY: CGFloat
        /// ⌥ was down, or the Range tool is in hand: a stretch of time on the
        /// tracks crossed, not the clips.
        let drawsRange: Bool
        var hasMoved = false
    }

    /// The box or the range being drawn, while the hand is down.
    struct LaneBox: Equatable {
        var range: Range<Int>
        var minY: CGFloat
        var maxY: CGFloat
        var tracks: [UUID]
        var drawsRange: Bool
    }

    /// How far a press on the tracks has to travel, in points, before it is a
    /// drag rather than a click.
    static let laneClickSlop: CGFloat = 3

    // MARK: The gesture

    /// The hand went down on empty track space at `ms`, `y` points down the
    /// tracks' own space.
    func beginLanePress(atMS ms: Int, y: CGFloat, drawsRange: Bool) {
        guard documentHasTime else { return }
        lanePress = LanePress(atMS: ms, atY: y, drawsRange: drawsRange)
        laneBoxDraft = nil
    }

    /// The hand moved to `ms`, `y`. `moved` says whether it has gone far
    /// enough to be a drag; `snapMS` is how near a cut or a marker pulls a
    /// range's moving end on (nought for a box, and with snapping off).
    func dragLanePress(toMS ms: Int, y: CGFloat, moved: Bool, snapMS: Int) {
        guard var press = lanePress, let document else { return }
        if moved, !press.hasMoved {
            press.hasMoved = true
            lanePress = press
        }
        guard press.hasMoved else { return }
        let length = document.documentDurationMS
        let range: Range<Int>?
        if press.drawsRange {
            let moments = snapMS > 0 ? document.rangeSnapMoments() : []
            range = RulerRange.drawn(fromMS: press.atMS, toMS: ms, lengthMS: length,
                                     snapTo: moments, reachMS: snapMS)
        } else {
            range = TimelineMarquee.stretch(fromMS: press.atMS, toMS: ms, lengthMS: length)
        }
        let minY = min(press.atY, y), maxY = max(press.atY, y)
        let tracks = TimelineMarquee.tracks(crossing: Double(minY)...Double(maxY), rows: laneRows)
        guard let range else {
            laneBoxDraft = nil
            return
        }
        laneBoxDraft = LaneBox(range: range, minY: minY, maxY: maxY, tracks: tracks,
                               drawsRange: press.drawsRange)
    }

    /// The hand came up at `ms`. A drag picks what the box touched, or the
    /// range it drew; a click moves the playhead and lets go of what was
    /// picked.
    func endLanePress(atMS ms: Int, moved: Bool) {
        guard let press = lanePress else { return }
        lanePress = nil
        let draft = laneBoxDraft
        laneBoxDraft = nil
        guard moved || press.hasMoved else {
            clickEmptyTrackSpace(atMS: ms)
            return
        }
        guard let draft else { return }
        if draft.drawsRange {
            pickTrackRange(TrackRange(range: draft.range, trackIDs: Set(draft.tracks)))
        } else {
            pickWithBox(within: draft.range, onTracks: Set(draft.tracks))
        }
    }

    /// Every track row on screen, for working out which a box crosses.
    private var laneRows: [TimelineMarquee.Row] {
        trackDropRows.values.map {
            TimelineMarquee.Row(trackID: $0.trackID, minY: Double($0.minY), maxY: Double($0.maxY))
        }
    }

    /// A click on empty track space: the playhead goes there and whatever was
    /// picked on the timeline is let go.
    private func clickEmptyTrackSpace(atMS ms: Int) {
        guard documentHasTime else { return }
        letGoOfTimelinePicks()
        if selectedLayerID != nil || !multiSelectedLayerIDs.isEmpty { selectLayer(nil) }
        if selectedEditPoint != nil { selectedEditPoint = nil }
        pauseDocument()
        scrubDocument(toMS: min(max(0, ms), lastDocumentTimeMS))
    }

    // MARK: Picking

    /// What a box over `range` on `tracks` touched becomes what is picked:
    /// whole clips as picked layers, one piece as the piece in hand, several
    /// pieces as the pieces picked. Nothing touched lets everything go.
    func pickWithBox(within range: Range<Int>, onTracks tracks: Set<UUID>) {
        guard documentHasTime, let document else { return }
        let picks = document.marqueePicks(within: range, onTracks: tracks)
        letGoOfTimelinePicks()
        rulerRangeInHand = nil
        if selectedEditPoint != nil { selectedEditPoint = nil }
        if picks.allSatisfy({ $0.piece == nil }) {
            selectLayers(Set(picks.map(\.layerID)))
        } else if picks.count == 1, let only = picks.first {
            selectClipPiece(layerID: only.layerID, index: only.piece)
        } else {
            selectLayer(nil)
            timelinePicks = picks
        }
    }

    /// A stretch of time on some tracks becomes the thing in hand: whatever
    /// was picked is let go, the way a Final Cut range replaces the clips.
    func pickTrackRange(_ range: TrackRange) {
        guard documentHasTime else { return }
        letGoOfTimelinePicks()
        guard !range.trackIDs.isEmpty else { return }
        if selectedLayerID != nil || !multiSelectedLayerIDs.isEmpty { selectLayer(nil) }
        if selectedEditPoint != nil { selectedEditPoint = nil }
        rulerRangeInHand = nil
        trackRangeInHand = range
    }

    /// Put down a box's pieces and a range on some tracks.
    func letGoOfTimelinePicks() {
        if !timelinePicks.isEmpty { timelinePicks = [] }
        if trackRangeInHand != nil { trackRangeInHand = nil }
    }

    /// The range on some tracks while it is still the thing in hand: nothing
    /// else has been picked since.
    var trackRangeHeld: TrackRange? {
        guard documentHasTime, let range = trackRangeInHand, selectedLayerID == nil,
              multiSelectedLayerIDs.isEmpty, selectedEditPoint == nil, !canDeletePickedKeys else { return nil }
        return range
    }

    /// The pieces a box picked, while they are still the thing in hand and
    /// every one of them is still there.
    var timelinePicksHeld: [TimelinePick]? {
        guard documentHasTime, !timelinePicks.isEmpty, selectedLayerID == nil,
              multiSelectedLayerIDs.isEmpty, let document,
              timelinePicks.allSatisfy({ document.span(of: $0) != nil }) else { return nil }
        return timelinePicks
    }

    /// Whether the box picked this piece of this clip.
    /// A clip picked whole among them lights every piece of it.
    func isPiecePickedByBox(layerID: UUID, index: Int) -> Bool {
        guard let picks = timelinePicksHeld else { return false }
        return picks.contains(TimelinePick(layerID: layerID, piece: index))
            || picks.contains(TimelinePick(layerID: layerID, piece: nil))
    }

    // MARK: What a range on some tracks, or the picked pieces, act on

    /// Whether ⌫ or ⇧⌫ has something to take: the range on some tracks runs
    /// over something there, or pieces are picked.
    var canTakeOutTrackThing: Bool {
        if timelinePicksHeld != nil { return true }
        guard let held = trackRangeHeld, let document else { return false }
        return document.canTakeOutStretch(fromMS: held.range.lowerBound, toMS: held.range.upperBound,
                                          onTracks: held.trackIDs)
    }

    /// ⌫: the range on some tracks, or the picked pieces, go and leave their
    /// gap. False where neither is in hand, so the press carries on.
    @discardableResult
    func liftTrackThing() -> Bool {
        if let picks = timelinePicksHeld {
            takeOut { $0.liftPicks(picks) }
            timelinePicks = []
            return true
        }
        guard let held = trackRangeHeld else { return false }
        takeOut { $0.liftStretch(fromMS: held.range.lowerBound, toMS: held.range.upperBound, onTracks: held.trackIDs) }
        trackRangeInHand = nil
        return true
    }

    /// ⇧⌫: the same, and the gap closes on those tracks alone.
    @discardableResult
    func extractTrackThing() -> Bool {
        if let picks = timelinePicksHeld {
            takeOut { $0.rippleDeletePicks(picks) }
            timelinePicks = []
            return true
        }
        guard let held = trackRangeHeld else { return false }
        takeOut { $0.extractStretch(fromMS: held.range.lowerBound, toMS: held.range.upperBound,
                                    onTracks: held.trackIDs) }
        // The stretch it named is gone; what is left there is the next thing.
        trackRangeInHand = nil
        return true
    }

    private func takeOut(_ edit: (inout PhotonzDocument) -> Bool) {
        guard var trial = document, edit(&trial) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { _ = edit(&$0) }
        selectedClipPieceIndex = nil
        if documentTimeMS > lastDocumentTimeMS { documentTimeMS = lastDocumentTimeMS }
        documentMomentChanged()
    }

    /// Split at Range Edges, on the tracks the range covers.
    var canSplitTrackRangeEdges: Bool {
        guard Experiments.shared.cutRecordingEnabled, let held = trackRangeHeld, var trial = document else {
            return false
        }
        return trial.splitEveryClip(atEdgesOf: held.range, onTracks: held.trackIDs) > 0
    }

    func splitTrackRangeEdges() {
        guard canSplitTrackRangeEdges, let held = trackRangeHeld else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.splitEveryClip(atEdgesOf: held.range, onTracks: held.trackIDs) }
        selectedClipPieceIndex = nil
        documentMomentChanged()
    }

    /// ⌘T: whether the range on some tracks has a cut inside it.
    var canAddTransitionInTrackRange: Bool {
        guard Experiments.shared.transitionsAtACutEnabled, let held = trackRangeHeld, let document else {
            return false
        }
        return !document.transitionCuts(within: held.range, onTracks: held.trackIDs).isEmpty
    }

    /// The default transition on every cut inside the range, on its tracks
    /// alone, as one step to undo; the canvas says how many took it.
    func addTransitionInTrackRange() {
        guard Experiments.shared.transitionsAtACutEnabled, let held = trackRangeHeld,
              var trial = document else { return }
        let kind = defaultTransitionKind
        let outcome = trial.putTransitionOnEveryCut(kind, within: held.range, onTracks: held.trackIDs)
        closeTransitionPicker()
        if !outcome.put.isEmpty {
            endTrimBeforeCutting()
            pauseDocument()
            perform { $0.putTransitionOnEveryCut(kind, within: held.range, onTracks: held.trackIDs) }
            documentMomentChanged()
        }
        raiseCanvasNotice(.transitionOnEveryCut(kind, outcome))
    }

    /// The rows a right click on the range, or on a picked piece, leads with.
    /// Empty when neither is in hand.
    func trackThingMenuRows() -> [MenuRow] {
        if timelinePicksHeld != nil {
            return [
                .command("Delete", TimelineMenuKeys.delete) { self.liftTrackThing() },
                .command("Ripple Delete", TimelineMenuKeys.rippleDelete) { self.extractTrackThing() },
            ]
        }
        guard trackRangeHeld != nil else { return [] }
        var rows: [MenuRow] = []
        if Experiments.shared.transitionsAtACutEnabled {
            rows.append(.command("Add Transition", TimelineMenuKeys.applyDefaultTransition,
                                 enabled: canAddTransitionInTrackRange) { self.addTransitionInTrackRange() })
        }
        rows.append(.command("Split at Range Edges", enabled: canSplitTrackRangeEdges) {
            self.splitTrackRangeEdges()
        })
        rows.append(.separator)
        let takesOut = canTakeOutTrackThing
        rows.append(.command("Delete", TimelineMenuKeys.delete, enabled: takesOut) { self.liftTrackThing() })
        rows.append(.command("Ripple Delete", TimelineMenuKeys.rippleDelete, enabled: takesOut) {
            self.extractTrackThing()
        })
        return rows
    }

    /// Whether a right click at `ms` on `track` is on the range in hand.
    func isOnTrackRange(atMS ms: Int, track: UUID) -> Bool {
        guard let held = trackRangeHeld else { return false }
        return held.trackIDs.contains(track) && (held.range.lowerBound...held.range.upperBound).contains(ms)
    }
}
