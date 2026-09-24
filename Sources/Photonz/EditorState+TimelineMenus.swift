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
// honour: M, I, O and E are Photoshop's tool keys in this app until the
// timeline owns the keyboard, so those rows print nothing yet.
//
// The rows are plain `MenuRow`s, the same list type the layer menus use, so a
// row reads the same wherever it is drawn. Each one picks what it was opened
// on before it acts, because a SwiftUI context menu cannot pick on the right
// click itself, and a command must never land on whatever happened to be
// picked before.
extension EditorState {

    // MARK: The keys the rows print

    enum TimelineMenuKeys {
        static let split = MenuShortcut(key: "b", modifiers: [])
        static let delete = MenuShortcut(key: DeleteKeyCharacters.backwards, modifiers: [])
        static let rippleDelete = MenuShortcut(key: DeleteKeyCharacters.backwards, modifiers: .option)
        static let detachAudio = MenuShortcut(key: "d", modifiers: [.control, .shift])
        static let duplicate = MenuShortcut.command("j")
        static let clearInOut = MenuShortcut(key: "x", modifiers: .option)
        static let splitEverything = MenuShortcut.commandShift("k")
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
        let piece = pieces.piece(at: index)
        let underPlayhead = time.contains(ms: documentTimeMS)

        rows.append(.command("Split at Playhead", TimelineMenuKeys.split, enabled: canSplitClip(layerID)) {
            self.selectLayer(layerID)
            self.splitClipAtPlayhead()
        })
        if layer.movie != nil {
            rows.append(.command("Freeze Frame", enabled: underPlayhead) {
                self.selectLayer(layerID)
                self.holdFrameAtPlayhead()
            })
        }
        if let piece, !piece.isHeld {
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
    /// clip when it is not. Nothing else moves, so a gap is left where a whole
    /// clip was, which is Premiere's Delete.
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
        if let markerHere {
            rows.append(.command("Remove Marker") { self.removeMarker(markerHere) })
        } else {
            rows.append(.command("Add Marker") { self.addMarker(atMS: ms) })
        }
        rows.append(.separator)
        rows.append(.command("Set In") { self.setMarkIn(atMS: ms) })
        rows.append(.command("Set Out") { self.setMarkOut(atMS: ms) })
        if document.markInMS != nil || document.markOutMS != nil {
            rows.append(.command("Clear In and Out", TimelineMenuKeys.clearInOut) { self.clearMarkInOut() })
        }
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
