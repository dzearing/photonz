import AppKit
import Foundation
import PhotonzCore

// What a right click offers on the timeline: on a clip, on a cut, on the ruler
// and the transport's scrub bar.
//
// A Premiere editor does not hunt for a tool or a panel button to act on a
// clip: they right click it. So every verb the timeline has lives here, on the
// thing it acts on, under Premiere's own names, with the key printed beside
// every row the app answers to. A row never prints a key the app does not
// honour: M, I and O are Photoshop's tool keys on the canvas, and the
// timeline's marks while it has the keyboard, which a right click in the dock
// has just handed it (`EditorState+TimelineKeys`).
//
// The rows are plain `MenuRow`s, the same list type the layer menus use, so a
// row reads the same wherever it is drawn. Each one picks what it was opened
// on before it acts, because a SwiftUI context menu cannot pick on the right
// click itself, and a command must never land on whatever happened to be
// picked before.
extension EditorState {

    // MARK: The keys the rows print

    enum TimelineMenuKeys {
        /// Premiere's Add Edit. B picks up the Blade.
        static let split = MenuShortcut.command("k")
        static let delete = MenuShortcut(key: DeleteKeyCharacters.backwards, modifiers: [])
        static let rippleDelete = MenuShortcut(key: DeleteKeyCharacters.backwards, modifiers: .option)
        static let detachAudio = MenuShortcut(key: "d", modifiers: [.control, .shift])
        static let duplicate = MenuShortcut.command("j")
        static let clearInOut = MenuShortcut(key: "x", modifiers: .option)
        static let splitEverything = MenuShortcut.commandShift("k")
        /// Premiere's marks. Plain letters, which the timeline answers while
        /// it has the keyboard (`EditorState+TimelineKeys`).
        static let addMarker = MenuShortcut(key: "m", modifiers: [])
        static let markIn = MenuShortcut(key: "i", modifiers: [])
        static let markOut = MenuShortcut(key: "o", modifiers: [])
        /// Premiere's Extract and Lift, on the same two keys.
        static let extract = MenuShortcut(key: "'", modifiers: [])
        static let lift = MenuShortcut(key: ";", modifiers: [])
    }

    // MARK: A clip

    /// The menu on one piece of a clip (the whole clip, when it is uncut).
    func timelineClipMenuRows(layerID: UUID, piece index: Int) -> [MenuRow] {
        guard let document, let layer = document.layer(id: layerID),
              let time = layer.time, let pieces = layer.clipPieces else { return [] }
        var rows: [MenuRow] = []
        // A clip on a locked track is not edited, and the menu says why by
        // offering the one thing that would change that.
        if isClipLocked(layerID) {
            if let track = document.trackID(ofClip: layerID) {
                rows.append(.command("Unlock Track") { self.toggleTrackLocked(track) })
                rows.append(.separator)
            }
            rows.append(.command("Rename…") { self.beginRenamingClip(layerID) })
            if let url = mediaURL(ofLayer: layerID) {
                rows.append(.command("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            }
            return rows
        }
        // A caption's verbs are the words and the track they are on.
        if layer.isCaption { return captionCueMenuRows(layerID: layerID) }
        let piece = pieces.piece(at: index)
        let underPlayhead = time.contains(ms: documentTimeMS)

        rows.append(.command("Split at Playhead", TimelineMenuKeys.split, enabled: canSplitClip(layerID)) {
            self.selectLayer(layerID)
            self.splitClipAtPlayhead()
        })
        if layer.movie != nil {
            rows.append(freezeFrameMenuRow(layerID: layerID, piece: index, enabled: underPlayhead))
            rows.append(contentsOf: punchInMenuRows(layerID: layerID, around: nil))
        }
        if let piece, !piece.isHeld, layer.hasMediaBehindIt {
            rows.append(.submenu("Speed", EditorState.clipSpeeds.map { percent in
                .toggle(ClipSpeed.title(percent), isOn: piece.speedPercent == percent) {
                    self.selectClipPiece(layerID: layerID, index: index)
                    self.setClipSpeedInHand(percent)
                }
            }))
        }
        let ends = transitionCuts(of: pieces, aroundPiece: index)
        if Experiments.shared.transitionsAtACutEnabled, !ends.isEmpty {
            rows.append(.submenu("Add Transition", ClipTransitionKind.allCases.map { kind in
                .command(kind.title, enabled: ends.contains { $0.canAfford(kind) }) {
                    self.addTransition(kind, layerID: layerID, atCuts: ends.map(\.index))
                }
            }))
        }
        if document.canDetachSound(ofLayer: layerID) {
            rows.append(.command("Detach Audio", TimelineMenuKeys.detachAudio) {
                self.selectLayer(layerID)
                self.detachSound()
            })
        }
        // A title, a piece of clip art: how it comes on and goes off.
        rows.append(contentsOf: titleAnimationMenuRows(layerID: layerID))
        // Keys copied off another layer land here at the playhead.
        if keysOnClipboard != nil { rows.append(pasteKeysRow(layerID: layerID)) }
        rows.append(.separator)
        rows.append(.command("Rename…") { self.beginRenamingClip(layerID) })
        rows.append(.command("Duplicate", TimelineMenuKeys.duplicate) { self.duplicateLayer(id: layerID) })
        if let url = mediaURL(ofLayer: layerID) {
            rows.append(.command("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        rows.append(.separator)
        let onePiece = pieces.count <= 1
        rows.append(.command("Delete", TimelineMenuKeys.delete, destructive: true) {
            self.deleteFromTimeline(layerID: layerID, piece: onePiece ? nil : index)
        })
        rows.append(.command("Ripple Delete", TimelineMenuKeys.rippleDelete, destructive: true) {
            self.rippleDelete(layerID: layerID, piece: onePiece ? nil : index)
        })
        return rows
    }

    /// **Freeze Frame ▸**: hold the frame under the playhead for a length, and
    /// say what the rest of the timeline does while it holds. On a piece that
    /// is already a hold, the lengths and the choice change THAT hold.
    ///
    /// The choices used to be a column of radio buttons and three sentences in
    /// the Time section; a freeze is a verb, so it lives on the clip.
    func freezeFrameMenuRow(layerID: UUID, piece index: Int, enabled: Bool) -> MenuRow {
        let piece = document?.layer(id: layerID)?.clipPieces?.piece(at: index)
        let held = piece?.isHeld == true
        var rows: [MenuRow] = ClipPieces.holdStopsMS.map { ms in
            if held {
                return .toggle("Hold for \(ClipPieces.holdTitle(ms))", isOn: piece?.lengthMS == ms) {
                    self.selectClipPiece(layerID: layerID, index: index)
                    self.setHoldLengthInHand(ms)
                }
            }
            return .command("Freeze for \(ClipPieces.holdTitle(ms))", enabled: enabled) {
                self.selectLayer(layerID)
                self.holdFrameAtPlayhead(forMS: ms)
            }
        }
        rows.append(.separator)
        let shown = piece?.holdPush ?? holdPushChoice
        rows.append(contentsOf: HoldPush.allCases.map { push in
            .toggle(push.title, isOn: shown == push) {
                if held { self.selectClipPiece(layerID: layerID, index: index) }
                self.setHoldPush(push)
            }
        })
        return .submenu("Freeze Frame", rows)
    }

    /// Whether the playhead runs through this clip somewhere a cut would
    /// mean anything, whichever clip is picked.
    func canSplitClip(_ id: UUID) -> Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, !isClipLocked(id),
              let layer = document?.layer(id: id), let time = layer.time,
              var pieces = layer.clipPieces,
              documentTimeMS > time.inMS, documentTimeMS < time.outMS else { return false }
        return pieces.split(atMS: documentTimeMS - time.inMS)
    }

    /// The cuts either side of a piece, which is where Premiere puts a
    /// transition you ask a clip for: at both of its ends.
    private func transitionCuts(of pieces: ClipPieces, aroundPiece index: Int) -> [ClipCut] {
        [index, index + 1].compactMap { pieces.cut(at: $0) }
    }

    /// Put one kind of transition on several cuts of one clip, as ONE step to
    /// undo. Each cut gets the longest it can pay for up to the usual length,
    /// and a cut that cannot pay for the kind at all is left as it was.
    func addTransition(_ kind: ClipTransitionKind, layerID: UUID, atCuts indices: [Int]) {
        guard Experiments.shared.transitionsAtACutEnabled,
              let pieces = document?.layer(id: layerID)?.clipPieces else { return }
        let planned: [(Int, ClipTransition)] = indices.compactMap { index in
            guard let cut = pieces.cut(at: index) else { return nil }
            let longest = cut.longestMS(of: kind)
            guard longest >= ClipTransition.shortestMS else { return nil }
            let asked = cut.transition?.lengthMS ?? ClipTransition.defaultLengthMS
            return (index, ClipTransition(kind: kind, lengthMS: min(max(ClipTransition.shortestMS, asked), longest)))
        }
        guard !planned.isEmpty else { return }
        endTrimBeforeCutting()
        pauseDocument()
        perform { document in
            for (index, transition) in planned { document.setClipTransition(layerID, atCut: index, to: transition) }
        }
        selectClipCut(layerID: layerID, index: planned[0].0)
        documentMomentChanged()
    }

    /// Delete from the timeline: the piece, when the clip is cut, and the whole
    /// clip when it is not. A piece takes its stretch out of everything with it
    /// (`deleteClipPieceInHand`); a whole clip leaves a gap where it was, which
    /// is Premiere's Delete.
    func deleteFromTimeline(layerID: UUID, piece index: Int?) {
        if let index {
            selectClipPiece(layerID: layerID, index: index)
            deleteClipPieceInHand()
        } else {
            selectLayer(layerID)
            deleteSelectedLayers()
        }
    }

    /// Ripple Delete: the same, and everything after it pulls back to close the
    /// gap (`TimelineMenuEdits.swift`).
    func rippleDelete(layerID: UUID, piece index: Int?) {
        guard documentHasTime, !isClipLocked(layerID),
              let time = document?.layer(id: layerID)?.time else { return }
        endTrimBeforeCutting()
        pauseDocument()
        if let index {
            let landing = time.inMS + (document?.layer(id: layerID)?.clipPieces?.startMS(ofPiece: index) ?? 0)
            perform { $0.rippleDeleteClipPiece(layerID, at: index) }
            selectClipPiece(layerID: layerID, index: nil)
            documentTimeMS = min(max(0, landing), lastDocumentTimeMS)
        } else {
            perform { $0.rippleDeleteLayer(layerID) }
            selectLayer(nil)
            documentTimeMS = min(max(0, time.inMS), lastDocumentTimeMS)
        }
        documentMomentChanged()
    }

    /// Whether ⌥⌫ has something to ripple delete: a picked piece of a cut
    /// clip, else the picked clip itself.
    var canRippleDeleteInHand: Bool {
        guard documentHasTime, let id = selectedLayerID, document?.layer(id: id)?.time != nil else { return false }
        return !isClipLocked(id)
    }

    /// ⌥⌫: ripple delete what is picked.
    func rippleDeleteInHand() {
        guard canRippleDeleteInHand, let id = selectedLayerID else { return }
        let count = document?.layer(id: id)?.clipPieces?.count ?? 1
        rippleDelete(layerID: id, piece: count > 1 ? selectedClipPieceIndex : nil)
    }

    /// The file a clip plays, where it is still on disk to be shown.
    func mediaURL(ofLayer id: UUID) -> URL? {
        guard let layer = document?.layer(id: id) else { return nil }
        let url = layer.movie.flatMap { MovieLibrary.shared.url(for: $0) }
            ?? layer.sound.flatMap { SoundLibrary.shared.url(for: $0) }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The menu on one caption on the Captions track.
    func captionCueMenuRows(layerID: UUID) -> [MenuRow] {
        var rows: [MenuRow] = [
            .command("Edit Words") { self.beginRenamingClip(layerID) },
            .command("Start Here") {
                self.selectLayer(layerID)
                self.moveDocumentPlayhead(toMS: self.document?.layer(id: layerID)?.time?.inMS ?? 0)
            },
            .separator,
        ]
        rows.append(contentsOf: captionTrackMenuRows())
        rows.append(.separator)
        rows.append(.command("Delete", TimelineMenuKeys.delete, destructive: true) {
            self.deleteFromTimeline(layerID: layerID, piece: nil)
        })
        return rows
    }

    /// What every place that is about captions as a whole offers: write them
    /// again, move the lot, write them out, take them off.
    func captionTrackMenuRows() -> [MenuRow] {
        [
            .command(hasCaptions ? "Write Captions Again" : "Write Captions",
                     enabled: canWriteCaptions) { self.writeCaptions() },
            .submenu("Timing", [
                .command("Earlier", enabled: canNudgeCaptions) { self.nudgeCaptions(byMS: -Self.captionNudgeMS) },
                .command("Later", enabled: canNudgeCaptions) { self.nudgeCaptions(byMS: Self.captionNudgeMS) },
            ]),
            .submenu("Export Subtitles", CaptionFileFormat.allCases.map { format in
                .command(format.title + "…", enabled: canExportCaptions) { self.exportCaptions(as: format) }
            }),
            .command("Clear Captions", enabled: canClearCaptions, destructive: true) { self.clearCaptions() },
        ]
    }

    /// Start typing a clip's name over its bar.
    func beginRenamingClip(_ id: UUID) {
        selectLayer(id)
        renamingClipID = id
    }

    // MARK: A cut

    /// The menu on one join of a clip.
    func timelineCutMenuRows(layerID: UUID, cut index: Int) -> [MenuRow] {
        guard let document, let layer = document.layer(id: layerID), layer.time != nil,
              let cut = layer.clipPieces?.cut(at: index), !isClipLocked(layerID) else { return [] }
        var rows: [MenuRow] = []
        if Experiments.shared.transitionsAtACutEnabled {
            rows.append(.submenu("Add Transition", ClipTransitionKind.allCases.map { kind -> MenuRow in
                if cut.transition?.kind == kind {
                    return .toggle(kind.title, isOn: true) {}
                }
                return .command(kind.title, enabled: cut.canAfford(kind)) {
                    self.addTransition(kind, layerID: layerID, atCuts: [index])
                }
            }))
            if cut.transition != nil {
                rows.append(.command("Remove Transition") {
                    self.selectClipCut(layerID: layerID, index: index)
                    self.setClipTransitionInHand(nil)
                })
            }
            rows.append(.separator)
        }
        var trial = document
        rows.append(.command("Roll Edit to Playhead",
                             enabled: trial.rollClipCut(layerID, atCut: index, toMS: documentTimeMS)) {
            self.rollCutToPlayhead(layerID: layerID, cut: index)
        })
        return rows
    }

    /// The menu on the edit point between two clips, or on the transition
    /// drawn over one.
    func timelineEditPointMenuRows(_ point: TimelineEditPoint) -> [MenuRow] {
        let place = TimelineCutPlace.edit(outgoing: point.outgoing, incoming: point.incoming)
        guard Experiments.shared.transitionsAtACutEnabled,
              let cut = document?.documentCut(at: place)?.cut,
              !isClipLocked(point.incoming), !isClipLocked(point.outgoing) else { return [] }
        var rows: [MenuRow] = [
            .submenu("Add Transition", ClipTransitionKind.allCases.map { kind -> MenuRow in
                if cut.transition?.kind == kind { return .toggle(kind.title, isOn: true) {} }
                return .command(kind.title, enabled: cut.canAfford(kind)) {
                    self.setTransition(kind, at: place)
                }
            })
        ]
        if cut.transition != nil {
            rows.append(.command("Remove Transition") {
                self.pickCut(place)
                self.setTransition(nil, at: place)
            })
        }
        return rows
    }

    /// Roll a join to where the playhead is: the piece before it grows by what
    /// the piece after it gives up, and the clip stays the length it was.
    func rollCutToPlayhead(layerID: UUID, cut index: Int) {
        guard documentHasTime, !isClipLocked(layerID) else { return }
        endTrimBeforeCutting()
        var trial = document
        guard trial?.rollClipCut(layerID, atCut: index, toMS: documentTimeMS) == true else { return }
        pauseDocument()
        perform { $0.rollClipCut(layerID, atCut: index, toMS: self.documentTimeMS) }
        selectClipCut(layerID: layerID, index: index)
        documentMomentChanged()
    }

    // MARK: The ruler and the scrub bar

    /// The menu on the ruler and the transport's scrub bar. Every row acts
    /// HERE, at the moment the pointer was over when the right click landed,
    /// and takes the playhead there first so what it did is in view.
    func timelineRulerMenuRows(atMS ms: Int, markerHere: UUID?) -> [MenuRow] {
        guard let document, documentHasTime else { return [] }
        var rows: [MenuRow] = []
        // What the marks are for: the stretch they enclose, out in one key.
        // A click ON the marked stretch is about that stretch, so the two
        // lead; the ruler sits at the foot of the screen, where a long menu
        // scrolls and its last rows are out of sight.
        let takesOut = canTakeOutMarkedStretch
        let onTheStretch = takesOut && document.markedRangeMS.map { ($0.lowerBound...$0.upperBound).contains(ms) } == true
        let extractAndLift: [MenuRow] = [
            .command("Extract", TimelineMenuKeys.extract) { self.extractMarkedStretch() },
            .command("Lift", TimelineMenuKeys.lift) { self.liftMarkedStretch() },
        ]
        if onTheStretch { rows += extractAndLift + [.separator] }
        if let markerHere {
            rows.append(.command("Remove Marker") { self.removeMarker(markerHere) })
        } else {
            rows.append(.command("Add Marker", TimelineMenuKeys.addMarker) { self.addMarker(atMS: ms) })
        }
        rows.append(.separator)
        rows.append(.command("Set In", TimelineMenuKeys.markIn) { self.setMarkIn(atMS: ms) })
        rows.append(.command("Set Out", TimelineMenuKeys.markOut) { self.setMarkOut(atMS: ms) })
        if document.markInMS != nil || document.markOutMS != nil {
            rows.append(.command("Clear In and Out", TimelineMenuKeys.clearInOut) { self.clearMarkInOut() })
        }
        if takesOut, !onTheStretch { rows += [.separator] + extractAndLift }
        rows.append(.separator)
        var trial = document
        rows.append(.command("Split Everything Here", TimelineMenuKeys.splitEverything,
                             enabled: trial.splitEveryClip(atMS: ms) > 0) {
            self.splitEverything(atMS: ms)
        })
        if !document.markers.isEmpty {
            rows.append(.separator)
            rows.append(.command("Clear All Markers") { self.removeAllMarkers() })
        }
        return rows
    }

    private func movePlayhead(toMS ms: Int) {
        pauseDocument()
        documentTimeMS = min(max(0, ms), lastDocumentTimeMS)
        documentMomentChanged()
    }

    func addMarker(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.addMarker(atMS: ms) }
    }

    func removeMarker(_ id: UUID) {
        perform { $0.removeMarker(id) }
    }

    func removeAllMarkers() {
        guard document?.markers.isEmpty == false else { return }
        perform { $0.removeAllMarkers() }
    }

    func setMarkIn(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.setMarkIn(atMS: ms) }
    }

    func setMarkOut(atMS ms: Int) {
        guard documentHasTime else { return }
        movePlayhead(toMS: ms)
        perform { $0.setMarkOut(atMS: ms) }
    }

    var canClearMarkInOut: Bool {
        documentHasTime && (document?.markInMS != nil || document?.markOutMS != nil)
    }

    /// ⌥X, Premiere's Clear In and Out.
    func clearMarkInOut() {
        guard canClearMarkInOut else { return }
        perform { $0.clearMarkInOut() }
    }

    /// Whether Extract and Lift have anything to take: an In or an Out is
    /// set and something unlocked runs into the stretch they enclose.
    var canTakeOutMarkedStretch: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime,
              var trial = document, trial.markedRangeMS != nil else { return false }
        return trial.liftMarkedStretch()
    }

    /// ', Premiere's Extract: what the In and the Out enclose comes out of
    /// every unlocked track and the gap closes, captions and titles and all
    /// (`MarkedStretch.swift`). One undo step. The playhead lands on the join.
    @discardableResult
    func extractMarkedStretch() -> Bool {
        takeOutMarkedStretch { $0.extractMarkedStretch() }
    }

    /// ;, Premiere's Lift: the same stretch out, and the gap left where it
    /// was, so nothing after it moves.
    @discardableResult
    func liftMarkedStretch() -> Bool {
        takeOutMarkedStretch { $0.liftMarkedStretch() }
    }

    private func takeOutMarkedStretch(_ edit: @escaping (inout PhotonzDocument) -> Bool) -> Bool {
        guard canTakeOutMarkedStretch, var trial = document,
              let range = trial.markedRangeMS, edit(&trial) else { return false }
        endTrimBeforeCutting()
        pauseDocument()
        perform { _ = edit(&$0) }
        selectedClipPieceIndex = nil
        documentTimeMS = min(max(0, range.lowerBound), lastDocumentTimeMS)
        documentMomentChanged()
        return true
    }

    var canSplitEverythingAtPlayhead: Bool {
        guard Experiments.shared.cutRecordingEnabled, documentHasTime, var trial = document else { return false }
        return trial.splitEveryClip(atMS: documentTimeMS) > 0
    }

    /// ⇧⌘K, Premiere's Add Edit to All Tracks: every clip the moment runs
    /// through is cut there.
    func splitEverything(atMS ms: Int) {
        endTrimBeforeCutting()
        movePlayhead(toMS: ms)
        guard var trial = document, trial.splitEveryClip(atMS: documentTimeMS) > 0 else { return }
        perform { $0.splitEveryClip(atMS: self.documentTimeMS) }
        selectedClipPieceIndex = nil
        documentMomentChanged()
    }
}
