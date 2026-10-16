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
// picked, the way a click beside the clips does in both editors. A click in
// the gap between two clips also picks that gap (`EditorState+TimelineGap`).
//
// The box picks everything it touches, not only clips: the zoom bars on a
// Zoom lane and the keys on the key lanes it crosses too
// (`TimelineBoxPick.swift`). Shift adds what it touches to what is picked and
// Command flips each thing in or out. It can start anywhere empty: a track, a
// gap, the space between two zoom bars, and the strip under the last track,
// which is always there, so a timeline whose tracks are full end to end still
// has somewhere to start one, the way Final Cut's empty area under the
// storyline and Premiere's empty tracks do. Taking hold of any one thing in
// the pick carries the lot by the same time, and Delete takes the lot, each as
// one step to undo.

extension EditorState {

    /// What one press on empty track space is doing.
    struct LanePress {
        let atMS: Int
        let atY: CGFloat
        /// ⌥ was down, or the Range tool is in hand: a stretch of time on the
        /// tracks crossed, not the clips.
        let drawsRange: Bool
        /// What a box does with what is already picked.
        var mode: BoxPickMode = .replace
        var hasMoved = false
        /// Where the gesture that made this press began, in its own view's
        /// space: what tells a press apart from the next one. Not the
        /// moment under it, which changes once the timeline scrolls at an
        /// edge (`TimelineEdgeScroll`).
        var startedAt: CGPoint?
    }

    /// ⇧ adds what a box touches to the pick, ⌘ flips each thing in or out,
    /// the way Shift and Command clicks do.
    enum BoxPickMode: Equatable {
        case replace, add, toggle

        static func from(_ flags: NSEvent.ModifierFlags) -> BoxPickMode {
            if flags.contains(.command) { return .toggle }
            if flags.contains(.shift) { return .add }
            return .replace
        }
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
    func beginLanePress(atMS ms: Int, y: CGFloat, drawsRange: Bool, mode: BoxPickMode = .replace,
                        startedAt: CGPoint? = nil) {
        guard documentHasTime else { return }
        timelineEdgeScroll.end()
        lanePress = LanePress(atMS: ms, atY: y, drawsRange: drawsRange, mode: mode, startedAt: startedAt)
        laneBoxDraft = nil
    }

    /// Where the hand is while a box or a range is drawn: across the lanes
    /// from their left hand edge, and down the tracks' own space. Held near
    /// an edge, the timeline scrolls that way and the box keeps reaching to
    /// the hand's place in what scrolled in (`TimelineEdgeScroll`).
    func laneBoxHand(laneX: CGFloat, contentY: CGFloat, snapMS: Int) {
        guard lanePress?.hasMoved == true else { return }
        timelineEdgeScroll.follow(.init(laneX: laneX, contentY: contentY), editor: self) { [weak self] scroll in
            guard let self, self.lanePress?.hasMoved == true, let hand = scroll.hand else { return false }
            let ms = TimelineLaneMarquee.ms(hand.laneX, self.timelineLaneWidth, self.motionStripRuler)
            self.dragLanePress(toMS: ms, y: hand.contentY ?? 0, moved: true, snapMS: snapMS)
            return true
        }
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
        timelineEdgeScroll.end()
        lanePress = nil
        let draft = laneBoxDraft
        laneBoxDraft = nil
        guard moved || press.hasMoved else {
            // A Shift or Command click beside the clips keeps what is picked.
            guard press.mode == .replace else { return }
            clickEmptyTrackSpace(atMS: ms, y: press.atY)
            return
        }
        guard let draft else { return }
        if draft.drawsRange {
            pickTrackRange(TrackRange(range: draft.range, trackIDs: Set(draft.tracks)))
        } else {
            pickWithBox(within: draft.range, onTracks: Set(draft.tracks),
                        span: draft.minY...draft.maxY, mode: press.mode)
        }
    }

    /// Every track row on screen, for working out which a box crosses.
    private var laneRows: [TimelineMarquee.Row] {
        trackDropRows.values.map {
            TimelineMarquee.Row(trackID: $0.trackID, minY: Double($0.minY), maxY: Double($0.maxY))
        }
    }

    /// A click on empty track space: the playhead goes there and whatever was
    /// picked on the timeline is let go. A click in a gap picks the gap.
    private func clickEmptyTrackSpace(atMS ms: Int, y: CGFloat) {
        guard documentHasTime else { return }
        letGoOfTimelinePicks()
        if selectedLayerID != nil || !multiSelectedLayerIDs.isEmpty { selectLayer(nil) }
        if selectedEditPoint != nil { selectedEditPoint = nil }
        pickTimelineGap(atMS: ms, y: y)
        pauseDocument()
        scrubDocument(toMS: min(max(0, ms), lastDocumentTimeMS))
    }

    // MARK: Picking

    /// What a box over `range` on `tracks`, `span` points down the tracks'
    /// own space, touched becomes what is picked: whole clips as picked
    /// layers, one piece as the piece in hand, several pieces as the pieces
    /// picked, and the zoom bars and keys it touched beside them. Only zooms
    /// or only keys are picked the way a click picks them. Nothing touched
    /// lets everything go. ⇧ and ⌘ (`mode`) add to what is picked or flip.
    func pickWithBox(within range: Range<Int>, onTracks tracks: Set<UUID>,
                     span: ClosedRange<CGFloat>? = nil, mode: BoxPickMode = .replace) {
        guard documentHasTime, let document else { return }
        var picks = document.marqueePicks(within: range, onTracks: tracks)
        var extras = span.map { extrasTouched(within: range, span: $0, in: document) } ?? TimelineBoxExtras()
        if mode != .replace {
            let before = boxPickNow(in: document)
            picks = Self.combine(before.picks, picks, mode)
            extras = Self.combine(before.extras, extras, mode)
        }
        applyBoxPick(picks, extras: extras)
    }

    /// The zoom bars and keys a box touches: those whose lane it crosses and
    /// that stand inside its stretch of time.
    private func extrasTouched(within range: Range<Int>, span: ClosedRange<CGFloat>,
                               in document: PhotonzDocument) -> TimelineBoxExtras {
        let down = Double(span.lowerBound)...Double(span.upperBound)
        var extras = TimelineBoxExtras()
        if canWorkWithZooms {
            for (clip, row) in zoomLaneRows
            where TimelineMarquee.reaches(down, minY: Double(row.lowerBound), maxY: Double(row.upperBound)) {
                let ids = document.marqueeZooms(within: range, onClip: clip)
                if !ids.isEmpty { extras.zooms[clip] = Set(ids) }
            }
        }
        var lanes: [UUID: Set<UUID>] = [:]
        for (lane, row) in keyLaneRows
        where TimelineMarquee.reaches(down, minY: Double(row.lowerBound), maxY: Double(row.upperBound)) {
            lanes[lane.layerID, default: []].insert(lane.motionID)
        }
        for (layer, motions) in lanes {
            let keys = document.marqueeKeys(within: range, layerID: layer, motionIDs: motions)
            if !keys.isEmpty { extras.keys[layer] = keys }
        }
        return extras
    }

    /// What is picked on the timeline right now, in a box's terms, for ⇧ and
    /// ⌘ to add to. A clip held only because its zoom or its keys are picked
    /// is not itself picked.
    private func boxPickNow(in document: PhotonzDocument) -> (picks: [TimelinePick], extras: TimelineBoxExtras) {
        var extras = boxExtrasHeld ?? TimelineBoxExtras()
        for ref in pickedZooms { extras.zooms[ref.layerID, default: []].insert(ref.zoomID) }
        if let keys = keySelection, !keys.refs.isEmpty {
            extras.keys[keys.layerID, default: []].formUnion(keys.refs)
        }
        if let picks = timelinePicksHeld { return (picks, extras) }
        let heldByAPart = boxExtrasHeld == nil && (selectedZoom != nil || keySelection?.refs.isEmpty == false)
        guard !heldByAPart else { return ([], extras) }
        if let id = selectedLayerID, let piece = selectedClipPieceIndex {
            return ([TimelinePick(layerID: id, piece: piece)], extras)
        }
        let onTimeline = Set(document.timelineClipLayers.map(\.id))
        let layers = actionableLayerIDs.filter { onTimeline.contains($0) }
        return (layers.sorted { $0.uuidString < $1.uuidString }.map { TimelinePick(layerID: $0, piece: nil) }, extras)
    }

    /// `before` with `touched` added (⇧) or flipped (⌘).
    static func combine(_ before: [TimelinePick], _ touched: [TimelinePick], _ mode: BoxPickMode) -> [TimelinePick] {
        var out = before
        for pick in touched {
            if let at = out.firstIndex(of: pick) {
                if mode == .toggle { out.remove(at: at) }
            } else {
                out.append(pick)
            }
        }
        // A clip picked whole holds all its pieces.
        let whole = Set(out.filter { $0.piece == nil }.map(\.layerID))
        return out.filter { $0.piece == nil || !whole.contains($0.layerID) }
    }

    static func combine(_ before: TimelineBoxExtras, _ touched: TimelineBoxExtras,
                        _ mode: BoxPickMode) -> TimelineBoxExtras {
        func merge<T: Hashable>(_ a: [UUID: Set<T>], _ b: [UUID: Set<T>]) -> [UUID: Set<T>] {
            var out = a
            for (id, set) in b {
                let now = out[id] ?? []
                out[id] = mode == .toggle ? now.symmetricDifference(set) : now.union(set)
            }
            return out.filter { !$0.value.isEmpty }
        }
        return TimelineBoxExtras(zooms: merge(before.zooms, touched.zooms), keys: merge(before.keys, touched.keys))
    }

    /// Make `picks` and `extras` what is picked.
    private func applyBoxPick(_ picks: [TimelinePick], extras: TimelineBoxExtras) {
        letGoOfTimelinePicks()
        rulerRangeInHand = nil
        if selectedEditPoint != nil { selectedEditPoint = nil }
        letGoOfZoom()
        clearKeySelection()
        guard !picks.isEmpty else {
            pickBoxedZoomsOrKeys(extras)
            return
        }
        if picks.allSatisfy({ $0.piece == nil }) {
            selectLayers(Set(picks.map(\.layerID)))
        } else if picks.count == 1, extras.isEmpty, let only = picks.first {
            selectClipPiece(layerID: only.layerID, index: only.piece)
        } else {
            selectLayer(nil)
            timelinePicks = picks
        }
        if !extras.isEmpty {
            boxExtras = extras
            boxExtrasOwner = boxPickOwnerNow
        }
    }

    /// A box that touched no clip: the zooms it touched are picked as a
    /// click picks them, else the keys on the layer it touched most of.
    private func pickBoxedZoomsOrKeys(_ extras: TimelineBoxExtras) {
        let refs = extras.zooms.flatMap { clip, ids in ids.map { ClipZoomRef(layerID: clip, zoomID: $0) } }
            .sorted { (zoom($0)?.startMS ?? 0, $0.zoomID.uuidString) < (zoom($1)?.startMS ?? 0, $1.zoomID.uuidString) }
        if let first = refs.first {
            guard refs.count > 1 else {
                pickZoom(first)
                return
            }
            if selectedLayerID != first.layerID { selectLayer(first.layerID) }
            selectedZoom = first
            pickedZooms = Set(refs)
            documentMomentChanged()
            return
        }
        if let (layer, keys) = extras.keys.max(by: { $0.value.count < $1.value.count }) {
            pickKeys(layerID: layer, keys, extending: false)
            return
        }
        selectLayer(nil)
    }

    /// The pick of clips a box's zooms and keys were made beside.
    struct BoxPickOwner: Equatable {
        let layer: UUID?
        let layers: Set<UUID>
        let picks: [TimelinePick]
    }

    var boxPickOwnerNow: BoxPickOwner {
        BoxPickOwner(layer: selectedLayerID, layers: multiSelectedLayerIDs, picks: timelinePicks)
    }

    /// The zoom bars and keys a box picked, while the clips it picked beside
    /// them are still what is picked.
    var boxExtrasHeld: TimelineBoxExtras? {
        guard documentHasTime, !boxExtras.isEmpty, boxExtrasOwner == boxPickOwnerNow else { return nil }
        return boxExtras
    }

    /// What the panel says about several things picked on the timeline at
    /// once: how many, and of what kinds. Nil for one thing, which the panel
    /// describes in full, and for zooms or keys alone, which have panels of
    /// their own.
    var timelinePickSummary: TimelinePickSummary? {
        guard documentHasTime, let document else { return nil }
        let extras = boxExtrasHeld
        var kinds: [String] = []
        var pieces = 0
        if let picks = timelinePicksHeld {
            for pick in picks {
                if pick.piece == nil, let layer = document.layer(id: pick.layerID) {
                    kinds.append(ClipLine.kind(of: layer))
                } else {
                    pieces += 1
                }
            }
        } else if extras != nil || multiSelectedLayerIDs.count > 1 {
            kinds = actionableLayerIDs.compactMap { document.layer(id: $0) }.map { ClipLine.kind(of: $0) }
        } else {
            return nil
        }
        return TimelinePickSummary(kinds: kinds, pieces: pieces, zooms: extras?.zoomCount ?? 0,
                                   keys: extras?.keyCount ?? 0)
    }

    /// Whether a box's pick lights this zoom's bar.
    func isZoomLitByBox(_ ref: ClipZoomRef) -> Bool {
        boxExtrasHeld?.zooms[ref.layerID]?.contains(ref.zoomID) == true
    }

    /// The keys a box's pick lights on a layer's lanes.
    func keysLitByBox(layerID: UUID) -> Set<KeyRef> {
        boxExtrasHeld?.keys[layerID] ?? []
    }

    // MARK: Carrying and deleting the whole pick

    /// What a clip carried by the hand brings with it from a box's pick: the
    /// zooms and keys on every clip that is not itself moving.
    func boxExtrasCarried(moving: Set<UUID>) -> TimelineBoxExtras {
        guard let held = boxExtrasHeld, timelinePicksHeld == nil,
              moving.contains(where: { actionableLayerIDs.contains($0) }) else { return TimelineBoxExtras() }
        return held.besides(moving)
    }

    /// A zoom bar or a key in a box's pick taken hold of: the whole pick is
    /// carried, through the clip bar's own drag on a clip of the pick (the
    /// zoom's own clip where that is picked), so it snaps as a clip does.
    /// False where the pick has no whole clip to carry it by.
    func beginBoxPickDrag(from clip: UUID) -> Bool {
        guard boxExtrasHeld != nil, timelinePicksHeld == nil else { return false }
        let layers = actionableLayerIDs
        guard let anchor = layers.contains(clip) ? clip
                : selectedLayerID ?? layers.min(by: { $0.uuidString < $1.uuidString }) else { return false }
        beginClipBarDrag(layerID: anchor, grab: .body)
        guard clipBarDrag != nil else { return false }
        dragCarriesBoxPick = true
        return true
    }

    /// The keys a carried pick left where they landed: a key is named by
    /// where it sits, so its name changed with it.
    func noteBoxExtrasLanded(_ landed: TimelineBoxExtras) {
        guard boxExtrasHeld != nil else { return }
        var now = boxExtras
        for (layer, keys) in landed.keys { now.keys[layer] = keys }
        boxExtras = now
    }

    /// Delete with a box's whole pick in hand: the clips or pieces and every
    /// zoom and key beside them, as one step. False where there is no such
    /// pick.
    @discardableResult
    func deleteBoxPick() -> Bool {
        guard let extras = boxExtrasHeld, let document else { return false }
        if let picks = timelinePicksHeld {
            let rest = extras.besides(Set(picks.filter { $0.piece == nil }.map(\.layerID)))
            takeOut { doc in
                let lifted = doc.liftPicks(picks)
                let removed = doc.removeBoxExtras(rest)
                return lifted || removed
            }
            timelinePicks = []
            boxExtras = TimelineBoxExtras()
            return true
        }
        let ids = document.deletableLayerIDs(in: actionableLayerIDs)
        let rest = extras.besides(actionableLayerIDs)
        guard !ids.isEmpty || !rest.isEmpty else { return false }
        discardDragPreview()
        endTrimBeforeCutting()
        pauseDocument()
        if let selected = selectedLayerID, ids.contains(selected) { selectedLayerID = nil }
        perform { doc in
            if !ids.isEmpty { doc.holdingTurnedPivots(above: Array(ids)) { $0.removeLayers(ids: ids) } }
            doc.removeBoxExtras(rest)
        }
        boxExtras = TimelineBoxExtras()
        setSelection(nil, captureLayers: false, recording: false)
        if documentTimeMS > lastDocumentTimeMS { documentTimeMS = lastDocumentTimeMS }
        documentMomentChanged()
        return true
    }

    /// ⇧⌫ with a box's whole pick in hand: the clips or pieces go and their
    /// gaps close on their own tracks, and every zoom and key beside them
    /// goes too, as one step. False where there is no such pick.
    @discardableResult
    func extractBoxPick() -> Bool {
        guard let extras = boxExtrasHeld, let document else { return false }
        let pieces = timelinePicksHeld
        let picks = pieces ?? document.timelineClipLayers.map(\.id)
            .filter { actionableLayerIDs.contains($0) && !isClipLocked($0) }
            .map { TimelinePick(layerID: $0, piece: nil) }
        // Whole clips leave the playhead where the earliest of them began,
        // as Ripple Delete on one clip does.
        let landing = pieces == nil ? picks.compactMap { document.layer(id: $0.layerID)?.time?.inMS }.min() : nil
        takeOut { $0.rippleDeleteBoxPick(picks, extras: extras) }
        timelinePicks = []
        boxExtras = TimelineBoxExtras()
        if pieces == nil { selectLayer(nil) }
        if let landing {
            documentTimeMS = min(max(0, landing), lastDocumentTimeMS)
            documentMomentChanged()
        }
        return true
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

    /// Put down a box's pieces, a range on some tracks and a picked gap.
    /// `keepingRange` leaves the range in hand, for a pick made under it
    /// (`EditorState+RangeSection`).
    func letGoOfTimelinePicks(keepingRange: Bool = false) {
        if !timelinePicks.isEmpty { timelinePicks = [] }
        if !boxExtras.isEmpty { boxExtras = TimelineBoxExtras() }
        if !keepingRange, trackRangeInHand != nil { trackRangeInHand = nil }
        if timelineGapInHand != nil { timelineGapInHand = nil }
    }

    /// The range on some tracks while it is the thing in hand on its own:
    /// nothing else has been picked since. A clip picked under it leaves it
    /// in hand, acting on the clip (`EditorState+RangeSection`).
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
        if boxExtrasHeld != nil, timelinePicksHeld != nil { return deleteBoxPick() }
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
        // A box's whole pick, the zooms and keys beside its clips included.
        if extractBoxPick() { return true }
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

/// One key lane: a layer's lane for one keyed value, for working out which a
/// box over the tracks crosses.
struct KeyLaneRowID: Hashable {
    let layerID: UUID
    let motionID: UUID
}
