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
    let place: TimelineCutPlace
    /// Which end is in the hand. Both ends do the same thing — the band grows
    /// or shrinks about the cut — because a transition is measured ACROSS the
    /// join and never sits to one side of it.
    let grabbedLeadingEdge: Bool
    let startedAtMS: Int
    /// What the length would be if you let go now.
    var landingMS: Int

    /// The clip whose bar the band is drawn on: the clip itself for a join,
    /// the arriving clip for a cut between two.
    var layerID: UUID { place.arrivingClip }
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

    /// **The cut the panel, the picker and the commands act on**, wherever it
    /// is: the edit point between two clips when one is picked, else the join
    /// of the clip in hand (`clipCutInHand`).
    var cutInHand: DocumentCut? {
        guard let document else { return nil }
        if let point = selectedEditPoint {
            return document.documentCut(at: .edit(outgoing: point.outgoing, incoming: point.incoming))
        }
        guard let id = clipInHandID, let cut = clipCutInHand else { return nil }
        return document.documentCut(at: .join(clip: id, index: cut.index))
    }

    /// Whether transitions are reachable at all: the switch is on, the document
    /// has time, and there is a cut to put one on — an edit point picked
    /// between two clips, or a clip in hand that has been cut at least once.
    var canWorkWithClipTransitions: Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime else { return false }
        if selectedEditPoint != nil { return cutInHand != nil }
        return !clipCutsInHand.isEmpty
    }

    /// What the cut in hand can take, in the order the picker offers them:
    /// every kind, each with whether this cut can pay for it.
    var clipTransitionOffers: [(kind: ClipTransitionKind, canAfford: Bool, longestMS: Int)] {
        guard let cut = cutInHand?.cut else { return [] }
        return ClipTransitionKind.allCases.map {
            ($0, cut.canAfford($0), cut.longestMS(of: $0))
        }
    }

    /// Put a transition on the cut in hand, or take one off with nil.
    func setClipTransitionInHand(_ kind: ClipTransitionKind?) {
        guard canWorkWithClipTransitions, let place = cutInHand?.place else { return }
        setTransition(kind, at: place)
    }

    /// Put a transition on a cut, or take one off with nil.
    ///
    /// The length is the one that was there, kept where the new kind can pay
    /// for it, else the usual length. **Clamped here, at the gesture, and
    /// refused by the model**: the surface knows what was meant and can say
    /// what it did; the model never guesses.
    func setTransition(_ kind: ClipTransitionKind?, at place: TimelineCutPlace) {
        guard Experiments.shared.transitionsAtACutEnabled,
              let cut = document?.documentCut(at: place)?.cut else { return }
        pauseDocument()
        guard let kind else {
            perform { $0.setTransition(nil, at: place) }
            documentMomentChanged()
            return
        }
        guard let transition = cut.fitted(kind) else { return }
        perform { $0.setTransition(transition, at: place) }
        pickCut(place)
        // The playhead goes to the cut, so the canvas shows what was just put
        // on it: both shots at once, or the colour it dips through.
        if let at = document?.documentCut(at: place)?.atMS {
            documentTimeMS = min(max(0, at), lastDocumentTimeMS)
        }
        documentMomentChanged()
    }

    /// How long the transition on the cut in hand is asked to be.
    func setClipTransitionLength(_ ms: Int) {
        guard canWorkWithClipTransitions, let inHand = cutInHand,
              let existing = inHand.cut.transition else { return }
        let longest = inHand.cut.longestMS(of: existing.kind)
        let length = min(max(ClipTransition.shortestMS, ms), longest)
        guard length != existing.lengthMS else { return }
        pauseDocument()
        perform {
            $0.setTransition(ClipTransition(kind: existing.kind, lengthMS: length), at: inHand.place)
        }
        documentMomentChanged()
    }

    /// The lengths the Length dropdown offers at the cut in hand: the usual
    /// stops this cut can pay for, the one it has now, and the longest it can
    /// take, in order.
    var clipTransitionLengthOffers: [Int] {
        guard let inHand = cutInHand, let kind = inHand.cut.transition?.kind else { return [] }
        let longest = inHand.cut.longestMS(of: kind)
        var stops = Set(ClipTransition.lengthStopsMS.filter { $0 <= longest })
        if let now = inHand.cut.drawnTransition?.lengthMS { stops.insert(now) }
        if longest >= ClipTransition.shortestMS, longest < 10_000 { stops.insert(longest) }
        return stops.sorted()
    }

    /// Pick a cut wherever it is, the way a click on it does.
    func pickCut(_ place: TimelineCutPlace) {
        switch place {
        case let .join(clip, index):
            selectClipCut(layerID: clip, index: index)
        case let .edit(outgoing, incoming):
            guard let trackID = document?.trackID(ofClip: incoming),
                  let point = document?.editPoints(onTrack: trackID)
                      .first(where: { $0.outgoing == outgoing && $0.incoming == incoming }) else { return }
            if selectedEditPoint != point { pickEditPoint(point) }
        }
    }

    // MARK: One key: the default transition

    /// What ⌘T puts on a cut: cross dissolve until somebody picks another
    /// (`DefaultTransitionStore`).
    var defaultTransitionKind: ClipTransitionKind { DefaultTransitionStore.shared.kind }

    /// Make `kind` the one ⌘T puts on a cut, in every document from now on.
    func setDefaultTransition(_ kind: ClipTransitionKind) {
        DefaultTransitionStore.shared.kind = kind
        raiseCanvasNotice(.defaultTransitionSet(kind))
    }

    /// The cut that is picked, when a cut is what is picked.
    private var pickedCutPlace: TimelineCutPlace? {
        if let point = selectedEditPoint {
            return .edit(outgoing: point.outgoing, incoming: point.incoming)
        }
        guard let id = clipInHandID, let index = selectedClipCutIndex else { return nil }
        return .join(clip: id, index: index)
    }

    /// What ⌘T would do now, or at one cut when a menu on that cut asks: the
    /// cut picked, else the one the playhead is standing on
    /// (`DefaultTransition.swift`). Nil where transitions are not reachable.
    func defaultTransitionPlan(at place: TimelineCutPlace? = nil) -> DefaultTransitionPlan? {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime, let document else { return nil }
        return document.defaultTransitionPlan(defaultTransitionKind, picked: place ?? pickedCutPlace,
                                              atMS: documentTimeMS, reachMS: clipCutReachMS)
    }

    func canApplyDefaultTransition(at place: TimelineCutPlace? = nil) -> Bool {
        guard case .put = defaultTransitionPlan(at: place) else { return false }
        return true
    }

    /// Final Cut's ⌘T, Premiere's ⌘D: the default transition on the cut
    /// picked, else the cut at the playhead, as one step to undo. Where there
    /// is no cut, or the cut cannot pay for it, the canvas says so rather than
    /// the key doing nothing. False only where transitions are not reachable,
    /// so the press carries on.
    @discardableResult
    func applyDefaultTransition(at place: TimelineCutPlace? = nil) -> Bool {
        guard let plan = defaultTransitionPlan(at: place) else { return false }
        switch plan {
        case .refused(let why):
            raiseCanvasNotice(.defaultTransitionRefused(why))
        case .put(let transition, let place):
            closeTransitionPicker()
            setTransition(transition.kind, at: place)
        }
        return true
    }

    // MARK: The picker at the cut

    /// Open the tiles at a cut (`video-transition-wt.html`, "At this cut").
    /// Picking the cut comes first, so the panel is already talking about the
    /// cut the picker is.
    func openTransitionPicker(at place: TimelineCutPlace, fromPanel: Bool = false) {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              document?.documentCut(at: place) != nil else { return }
        pickCut(place)
        transitionPickerFromPanel = fromPanel
        transitionPickerPlace = place
    }

    /// Put the tiles away.
    func closeTransitionPicker() {
        if transitionPickerPlace != nil { transitionPickerPlace = nil }
    }

    // MARK: The band under a hand

    /// Take hold of one end of the band drawn over a cut.
    func beginClipTransitionDrag(place: TimelineCutPlace, leadingEdge: Bool) {
        guard let drawn = document?.documentCut(at: place)?.cut.drawnTransition else { return }
        pauseDocument()
        closeTransitionPicker()
        pickCut(place)
        clipTransitionDrag = ClipTransitionDragSession(place: place,
                                                       grabbedLeadingEdge: leadingEdge,
                                                       startedAtMS: drawn.lengthMS,
                                                       landingMS: drawn.lengthMS)
        watchForClipTransitionEscape()
    }

    /// Take hold of one end of the band over one of a clip's own joins.
    func beginClipTransitionDrag(layerID: UUID, cutIndex: Int, leadingEdge: Bool) {
        beginClipTransitionDrag(place: .join(clip: layerID, index: cutIndex), leadingEdge: leadingEdge)
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
              let cut = document?.documentCut(at: session.place)?.cut,
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
              let kind = document?.documentCut(at: session.place)?.cut.transition?.kind else { return }
        perform {
            $0.setTransition(ClipTransition(kind: kind, lengthMS: session.landingMS), at: session.place)
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
        guard let kind = document.documentCut(at: session.place)?.cut.transition?.kind else {
            return document
        }
        document.setTransition(ClipTransition(kind: kind, lengthMS: session.landingMS), at: session.place)
        return document
    }

    /// What the capsule over the band says while it is being dragged.
    var clipTransitionReadout: String? {
        guard let session = clipTransitionDrag else { return nil }
        return ClipTransitionCopy.seconds(session.landingMS)
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
