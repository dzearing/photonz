import Foundation
import PhotonzCore

// A range of time drawn on the ruler, and what it acts on (`RulerRange.swift`).
//
// Drag along the ruler and the stretch dragged over is marked across every
// track, the In and the Out set together as one undo step. A press on the
// playhead still scrubs, a press on either end of the band moves that end,
// and a click moves the playhead and, outside the band, lets it go.
//
// A range just drawn is the thing in hand: nothing else is picked, it is
// washed down through every track, ⌫ lifts it, ⇧⌫ (and ⌥⌫) takes it out and
// closes the gap, ⌘T puts the default transition on every cut inside it, and
// a click on the ruler outside it lets it go. Picking anything else puts it
// down, and the marks stay on the ruler as marks.

extension EditorState {

    /// What one press on the ruler is doing: what it took hold of, where it
    /// landed, and the marked stretch it started from.
    struct RulerPress {
        let grip: RulerGrip
        let atMS: Int
        let range: Range<Int>?
        /// It has gone far enough to be a drag, and stays one if the hand
        /// comes back to where it started.
        var hasMoved = false
    }

    /// How far a press has to travel, in points, before it is a drag rather
    /// than a click.
    static let rulerClickSlop: CGFloat = 3

    // MARK: The gesture

    /// The hand went down on the ruler at `ms`. `reachMS` is how near the
    /// playhead or an end of the band it has to be to take hold of it.
    func beginRulerPress(atMS ms: Int, reachMS: Int) {
        guard documentHasTime, let document else { return }
        let grip = RulerRange.grip(atMS: ms, playheadMS: documentTimeMS,
                                   markInMS: document.markInMS, markOutMS: document.markOutMS,
                                   reachMS: reachMS)
        rulerPress = RulerPress(grip: grip, atMS: ms, range: document.markedRangeMS)
        if grip == .playhead { beginPlayheadDrag() }
    }

    /// The hand moved to `ms`. `moved` says whether it has gone far enough
    /// to be a drag; `snapMS` is how near a cut or a marker pulls an end on,
    /// nought with snapping off (`keySnapReachMS(laneWidth:)`).
    func dragRulerPress(toMS ms: Int, moved: Bool, snapMS: Int) {
        guard var press = rulerPress, let document else { return }
        if moved, !press.hasMoved {
            press.hasMoved = true
            rulerPress = press
        }
        let moved = press.hasMoved
        let length = document.documentDurationMS
        let moments = snapMS > 0 ? document.rangeSnapMoments() : []
        switch press.grip {
        case .playhead:
            dragPlayhead(toMS: ms, snappingWithinMS: snapMS)
        case .inEdge, .outEdge:
            guard moved, let range = press.range else { return }
            rulerRangeDraft = RulerRange.moving(press.grip, of: range, toMS: ms, lengthMS: length,
                                                snapTo: moments, reachMS: snapMS)
        case .newRange:
            guard moved else { return }
            rulerRangeDraft = RulerRange.drawn(fromMS: press.atMS, toMS: ms, lengthMS: length,
                                               snapTo: moments, reachMS: snapMS)
        }
    }

    /// The hand came up at `ms`. A drag writes the band it drew to the In and
    /// the Out; a click moves the playhead there.
    func endRulerPress(atMS ms: Int, moved: Bool) {
        guard let press = rulerPress else { return }
        let moved = moved || press.hasMoved
        rulerPress = nil
        let draft = rulerRangeDraft
        rulerRangeDraft = nil
        switch press.grip {
        case .playhead:
            endPlayheadDrag()
        case .inEdge, .outEdge, .newRange:
            if moved {
                if let draft { markRulerRange(draft) }
            } else {
                clickRuler(atMS: ms)
            }
        }
    }

    /// A press that never moved: the playhead goes where it landed, and a
    /// range drawn on the ruler goes too when the click was outside it, the
    /// way a click beside a Final Cut range drops it. Marks set with I and O
    /// are marks, and stay where they were put, as in Premiere.
    private func clickRuler(atMS ms: Int) {
        guard documentHasTime, let document else { return }
        if rulerRangeHeld != nil, document.clickOnRulerClearsMarks(atMS: ms) {
            perform { $0.clearMarkInOut() }
            rulerRangeInHand = nil
        }
        pauseDocument()
        scrubDocument(toMS: min(max(0, ms), lastDocumentTimeMS))
    }

    /// Set the In and the Out to `range` in one undo step and make it the
    /// thing in hand: whatever was picked is let go, the way a Final Cut range
    /// replaces the clips that were selected.
    func markRulerRange(_ range: Range<Int>) {
        guard documentHasTime, let document else { return }
        if document.markedRangeMS != range || document.markInMS == nil || document.markOutMS == nil {
            perform { $0.markRange(range) }
        }
        if selectedLayerID != nil || !multiSelectedLayerIDs.isEmpty { selectLayer(nil) }
        if selectedEditPoint != nil { selectedEditPoint = nil }
        letGoOfTimelinePicks()
        rulerRangeInHand = self.document?.markedRangeMS
    }

    /// The range drawn on the ruler, while it is still the thing in hand: the
    /// marks have not moved since and nothing else has been picked.
    var rulerRangeHeld: Range<Int>? {
        guard documentHasTime, let range = rulerRangeInHand, document?.markedRangeMS == range,
              selectedLayerID == nil, multiSelectedLayerIDs.isEmpty, selectedEditPoint == nil,
              !canDeletePickedKeys else { return nil }
        return range
    }

    /// What the band on the ruler shows: the stretch being drawn while the
    /// hand is down, else the marked one.
    var rulerRangeShown: Range<Int>? {
        rulerRangeDraft ?? document?.markedRangeMS
    }

    // MARK: What a range acts on

    /// Split at Range Edges: a cut through every clip at both ends.
    var canSplitAtRangeEdges: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, var trial = document,
              let range = trial.markedRangeMS else { return false }
        return trial.splitEveryClip(atEdgesOf: range) > 0
    }

    func splitAtRangeEdges() {
        guard canSplitAtRangeEdges, let range = document?.markedRangeMS else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.splitEveryClip(atEdgesOf: range) }
        selectedClipPieceIndex = nil
        documentMomentChanged()
    }

    /// Merge into One Clip: whether any track has a clip under the marked
    /// stretch to merge (`MergedClip.swift`).
    var canMergeRange: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              let document, let range = document.markedRangeMS else { return false }
        return document.canMergeRange(range)
    }

    /// On every track, the parts of the clips inside the marked stretch become
    /// one clip, as one step to undo, and the clips it made are picked, the
    /// way Final Cut picks the compound clip it just made.
    func mergeRangeIntoOneClip() {
        guard canMergeRange, let range = document?.markedRangeMS else { return }
        endTrimBeforeCutting()
        pauseDocument()
        var made: [UUID] = []
        perform { made = $0.mergeRange(range) }
        selectedClipPieceIndex = nil
        rulerRangeInHand = nil
        if !made.isEmpty { selectLayers(Set(made)) }
        documentMomentChanged()
    }

    /// Break Apart: the clips a merged clip holds, back on its track, picked.
    func breakApartClip(_ id: UUID) {
        guard let document, document.canBreakApart(id) else { return }
        endTrimBeforeCutting()
        pauseDocument()
        var freed: [UUID] = []
        perform { freed = $0.breakApart(id) }
        selectedClipPieceIndex = nil
        if !freed.isEmpty { selectLayers(Set(freed)) }
        documentMomentChanged()
    }

    /// Add Transition: whether the marked stretch has a cut inside it.
    var canAddTransitionInRange: Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              let document, let range = document.markedRangeMS else { return false }
        return !document.transitionCuts(within: range).isEmpty
    }

    /// The default transition on every cut inside the marked stretch, as one
    /// step to undo; the canvas says how many took it.
    func addTransitionInRange() {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              var trial = document, let range = trial.markedRangeMS else { return }
        let kind = defaultTransitionKind
        let outcome = trial.putTransitionOnEveryCut(kind, within: range)
        closeTransitionPicker()
        if !outcome.put.isEmpty {
            endTrimBeforeCutting()
            pauseDocument()
            perform { $0.putTransitionOnEveryCut(kind, within: range) }
            documentMomentChanged()
        }
        raiseCanvasNotice(.transitionOnEveryCut(kind, outcome))
    }

    /// Add Captions for Range: listen, and write captions for this stretch
    /// alone, leaving every line outside it as it was.
    var canAddCaptionsInRange: Bool {
        canWriteCaptions && document?.markedRangeMS != nil
    }

    func addCaptionsInRange() {
        guard canAddCaptionsInRange, let range = document?.markedRangeMS else { return }
        writeCaptions(within: range)
    }

    /// Export Range: the export sheet, which writes In to Out whenever the
    /// marks are set (`VideoExportRange`).
    func exportRange() {
        guard documentHasTime, document?.markedRangeMS != nil, videoExport == nil else { return }
        pauseDocument()
        isExportDialogPresented = true
    }

    /// The rows a right click on the marked stretch leads with.
    func rulerRangeMenuRows() -> [MenuRow] {
        let held = rulerRangeHeld != nil
        var rows: [MenuRow] = []
        if Experiments.shared.transitionsAtACutEnabled {
            rows.append(.command("Add Transition", held ? TimelineMenuKeys.applyDefaultTransition : nil,
                                 enabled: canAddTransitionInRange) { self.addTransitionInRange() })
        }
        rows.append(.command("Split at Range Edges", enabled: canSplitAtRangeEdges) { self.splitAtRangeEdges() })
        rows.append(.command("Merge into One Clip", enabled: canMergeRange) { self.mergeRangeIntoOneClip() })
        rows.append(.separator)
        let takesOut = canTakeOutMarkedStretch
        rows.append(.command("Cut", held ? RangeClipboardKeys.cut : nil, enabled: takesOut) {
            self.cutMarkedRange()
        })
        rows.append(.command("Copy", held ? RangeClipboardKeys.copy : nil, enabled: takesOut) {
            self.copyMarkedRange()
        })
        rows.append(.command("Delete", held ? TimelineMenuKeys.delete : nil, enabled: takesOut) {
            self.liftMarkedStretch()
        })
        rows.append(.command("Ripple Delete", held ? TimelineMenuKeys.rippleDelete : nil,
                             enabled: takesOut) {
            self.extractMarkedStretch()
        })
        if Experiments.shared.captionsFromTheSoundEnabled, !isWritingCaptions {
            rows.append(.separator)
            rows.append(.command("Add Captions for Range", enabled: canAddCaptionsInRange) {
                self.addCaptionsInRange()
            })
        }
        rows.append(.command("Export Range…") { self.exportRange() })
        return rows
    }
}
