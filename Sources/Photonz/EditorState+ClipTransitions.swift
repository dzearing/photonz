import AppKit
import Foundation
import PhotonzCore

// A transition at a cut, in the hand (`docs/design/video-transitions.md`).
//
// The arithmetic is all in `PhotonzCore` (`ClipTransitions.swift`); this is the
// thin layer between it and a person: which cut is picked, what the menu and
// the panel are allowed to offer, and making a drag on the band one step to
// undo.
//
// **A cut is a thing you can pick.** Until this, a timeline had two kinds of
// selection — a clip and a piece of one — and a cut was the gap between two
// pieces with nothing to click. Now it is a third, and the panel speaks for it
// like it speaks for anything else picked.

/// The band under a hand: which cut it is on, what it was when it was grabbed,
/// and how long the hand has made it.
struct ClipTransitionDragSession: Equatable {
    let layerID: UUID
    let cutIndex: Int
    /// Which end is in the hand. Both ends do the same thing — the band grows
    /// or shrinks about the cut — because a transition is measured ACROSS the
    /// join and never sits to one side of it.
    let grabbedLeadingEdge: Bool
    let startedAtMS: Int
    /// What the length would be if you let go now.
    var landingMS: Int
}

extension EditorState {

    // MARK: Which cut is in hand

    /// The cuts of the clip the timeline's edits act on.
    var clipCutsInHand: [ClipCut] {
        guard let id = clipInHandID else { return [] }
        return document?.layer(id: id)?.clipCuts ?? []
    }

    /// The cut the panel and the commands act on: the one picked, else the one
    /// nearest the playhead when the playhead is close enough to mean it.
    ///
    /// The same rule the rest of the timeline follows — a person looking at a
    /// frame has already said where they are — with a distance on it, because
    /// "the nearest cut" in an eight second recording with one join is a cut
    /// four seconds away, and acting on that is acting somewhere nobody was
    /// looking.
    var clipCutInHand: ClipCut? {
        let cuts = clipCutsInHand
        guard !cuts.isEmpty else { return nil }
        if let picked = selectedClipCutIndex,
           let cut = cuts.first(where: { $0.index == picked }) { return cut }
        guard let id = clipInHandID, let start = document?.layer(id: id)?.time?.inMS else { return nil }
        let atMS = documentTimeMS - start
        let nearest = cuts.min { abs($0.atMS - atMS) < abs($1.atMS - atMS) }
        guard let nearest, abs(nearest.atMS - atMS) <= clipCutReachMS else { return nil }
        return nearest
    }

    /// How near the playhead has to be to a cut to count as standing on it: a
    /// second, or less on a short recording. A share of the document rather
    /// than a fixed number, for the reason the catching distance is one.
    var clipCutReachMS: Int { max(200, min(1000, documentLengthMS / 8)) }

    /// Pick a cut. Picking one picks its clip and lets go of any piece, so the
    /// panel is talking about one thing.
    func selectClipCut(layerID: UUID, index: Int?) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        selectedClipPieceIndex = nil
        selectedClipCutIndex = index
        // The playhead goes to the cut, so the canvas is showing the frames the
        // panel is talking about. Picking a cut and then hunting for it with
        // the scrubber would be doing the same thing twice.
        if let index, let start = document?.layer(id: layerID)?.time?.inMS,
           let cut = document?.layer(id: layerID)?.clipPieces?.cut(at: index) {
            documentTimeMS = min(max(0, start + cut.atMS), lastDocumentTimeMS)
            documentMomentChanged()
        }
    }

    // MARK: What can go on it

    /// Whether transitions are reachable at all: the switch is on, the document
    /// has time, and the clip in hand has been cut at least once. A recording
    /// nobody has cut has no join to put anything on, and saying so by having
    /// no command is better than a command that explains itself afterwards.
    var canWorkWithClipTransitions: Bool {
        Experiments.shared.transitionsAtACutEnabled && documentHasTime && !clipCutsInHand.isEmpty
    }

    /// What the cut in hand can take, in the order the panel offers them: every
    /// kind, each with whether this cut can pay for it and why not.
    var clipTransitionOffers: [(kind: ClipTransitionKind, canAfford: Bool, longestMS: Int)] {
        guard let cut = clipCutInHand else { return [] }
        return ClipTransitionKind.allCases.map {
            ($0, cut.canAfford($0), cut.longestMS(of: $0))
        }
    }

    /// Put a transition on the cut in hand, or take one off with nil.
    ///
    /// The length is the one that was there, kept where the new kind can pay
    /// for it, else what the panel offers by default. **Clamped here, at the
    /// gesture, and refused by the model**: the surface knows what was meant
    /// and can say what it did; the model never guesses.
    func setClipTransitionInHand(_ kind: ClipTransitionKind?) {
        guard canWorkWithClipTransitions, let cut = clipCutInHand,
              let id = clipInHandID else { return }
        pauseDocument()
        guard let kind else {
            perform { $0.setClipTransition(id, atCut: cut.index, to: nil) }
            documentMomentChanged()
            return
        }
        let longest = cut.longestMS(of: kind)
        guard longest >= ClipTransition.shortestMS else { return }
        let asked = cut.transition?.lengthMS ?? ClipTransition.defaultLengthMS
        let length = min(max(ClipTransition.shortestMS, asked), longest)
        perform {
            $0.setClipTransition(id, atCut: cut.index,
                                 to: ClipTransition(kind: kind, lengthMS: length))
        }
        selectClipCut(layerID: id, index: cut.index)
        documentMomentChanged()
    }

    /// How long the transition on the cut in hand is asked to be.
    func setClipTransitionLength(_ ms: Int) {
        guard canWorkWithClipTransitions, let cut = clipCutInHand,
              let existing = cut.transition, let id = clipInHandID else { return }
        let longest = cut.longestMS(of: existing.kind)
        let length = min(max(ClipTransition.shortestMS, ms), longest)
        guard length != existing.lengthMS else { return }
        pauseDocument()
        perform {
            $0.setClipTransition(id, atCut: cut.index,
                                 to: ClipTransition(kind: existing.kind, lengthMS: length))
        }
        documentMomentChanged()
    }

    // MARK: The band under a hand

    /// Take hold of one end of the band drawn over a cut.
    func beginClipTransitionDrag(layerID: UUID, cutIndex: Int, leadingEdge: Bool) {
        guard let cut = document?.layer(id: layerID)?.clipPieces?.cut(at: cutIndex),
              let drawn = cut.drawnTransition else { return }
        pauseDocument()
        selectClipCut(layerID: layerID, index: cutIndex)
        clipTransitionDrag = ClipTransitionDragSession(layerID: layerID, cutIndex: cutIndex,
                                                       grabbedLeadingEdge: leadingEdge,
                                                       startedAtMS: drawn.lengthMS,
                                                       landingMS: drawn.lengthMS)
        watchForClipTransitionEscape()
    }

    /// The hand moved. Nothing is written down: the bar and the canvas both
    /// read the landing, so the band follows the hand and the whole drag is
    /// still one step to undo.
    ///
    /// Dragging the LEFT end left makes it longer, and the right end right does
    /// the same, because both ends move away from the cut. The band grows by
    /// twice what the hand travelled: the other end moves with it, since a
    /// transition is measured across the join.
    func updateClipTransitionDrag(byMS delta: Int) {
        guard var session = clipTransitionDrag,
              let cut = document?.layer(id: session.layerID)?.clipPieces?.cut(at: session.cutIndex),
              let kind = cut.transition?.kind else { return }
        let travelled = session.grabbedLeadingEdge ? -delta : delta
        let longest = cut.longestMS(of: kind)
        session.landingMS = min(max(ClipTransition.shortestMS, session.startedAtMS + travelled * 2),
                                longest)
        clipTransitionDrag = session
        rerender()
    }

    /// Let go: one step for undo covering the whole drag.
    func commitClipTransitionDrag() {
        stopWatchingForClipTransitionEscape()
        guard let session = clipTransitionDrag else { return }
        clipTransitionDrag = nil
        guard session.landingMS != session.startedAtMS,
              let cut = document?.layer(id: session.layerID)?.clipPieces?.cut(at: session.cutIndex),
              let kind = cut.transition?.kind else { return }
        perform {
            $0.setClipTransition(session.layerID, atCut: session.cutIndex,
                                 to: ClipTransition(kind: kind, lengthMS: session.landingMS))
        }
        documentMomentChanged()
    }

    func cancelClipTransitionDrag() {
        stopWatchingForClipTransitionEscape()
        guard clipTransitionDrag != nil else { return }
        clipTransitionDrag = nil
        documentMomentChanged()
    }

    /// `document` with the band under the hand written into it, so the canvas
    /// plays the length the HAND has rather than the one still written down.
    /// One model, two views, exactly as a bar drag already is.
    func withDraggedClipTransition(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let session = clipTransitionDrag else { return document }
        var document = document
        guard let kind = document.layer(id: session.layerID)?
            .clipPieces?.transition(atCut: session.cutIndex)?.kind else { return document }
        document.setClipTransition(session.layerID, atCut: session.cutIndex,
                                   to: ClipTransition(kind: kind, lengthMS: session.landingMS))
        return document
    }

    /// What the capsule over the band says while it is being dragged.
    var clipTransitionReadout: String? {
        guard let session = clipTransitionDrag else { return nil }
        return ClipTransitionCopy.length(session.landingMS)
    }

    private func watchForClipTransitionEscape() {
        guard clipTransitionEscapeWatch == nil else { return }
        clipTransitionEscapeWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, clipTransitionDrag != nil else { return event }
            cancelClipTransitionDrag()
            return nil
        }
    }

    private func stopWatchingForClipTransitionEscape() {
        guard let watch = clipTransitionEscapeWatch else { return }
        NSEvent.removeMonitor(watch)
        clipTransitionEscapeWatch = nil
    }
}
