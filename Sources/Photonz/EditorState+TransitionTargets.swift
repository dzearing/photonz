import Foundation
import PhotonzCore

// Putting a transition where the clips meet (`TransitionTargets.swift`): from
// a clip's right click, the ruler's, a tile let go over the timeline and a
// tile clicked in the panel. Every door comes through `putTransition`, so each
// says the same thing when a place cannot take what was asked, and offers what
// it can take.
extension EditorState {

    /// Put `kind` on each of `targets` as ONE step to undo: a cut gets the
    /// transition, an end of a clip that meets nothing fades. Whatever could
    /// not take it is said on the canvas, and a cut with no spare frames is
    /// offered the kind it can take. False where nothing went on.
    @discardableResult
    func putTransition(_ kind: ClipTransitionKind, on targets: [TransitionTarget]) -> Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              var trial = document, !targets.isEmpty else { return false }
        let starved = targets.compactMap { target -> TimelineCutPlace? in
            guard case .cut(let place) = target,
                  case .refused(.noSpare) = trial.transitionPlan(kind, on: target) else { return nil }
            return place
        }
        let outcome = trial.putTransition(kind, on: targets)
        if let first = outcome.put.first {
            endTrimBeforeCutting()
            pauseDocument()
            closeTransitionPicker()
            perform { _ = $0.putTransition(kind, on: targets) }
            show(first)
            documentMomentChanged()
        }
        if let place = starved.first {
            let offer = document?.nearestTransition(to: kind, at: place)
            let action: CanvasNoticeAction? = offer.flatMap { $0 == kind ? nil : .putTransition($0, at: place) }
            // Something else took it: say which cut did not, not that
            // nothing went on.
            if !outcome.put.isEmpty, let at = document?.documentCut(at: place)?.atMS {
                raiseCanvasNotice(.transitionCutSkipped(atMS: at), action: action)
            } else {
                raiseCanvasNotice(.defaultTransitionRefused(.noSpare(kind)), action: action)
            }
        } else if outcome.put.isEmpty, let why = outcome.refused.first {
            raiseCanvasNotice(.defaultTransitionRefused(why))
        }
        return !outcome.put.isEmpty
    }

    /// Pick what was just put on and take the playhead to the middle of it,
    /// so the canvas shows it: both shots at once half way through a
    /// dissolve, half way up a fade.
    private func show(_ target: TransitionTarget) {
        guard let document else { return }
        switch target {
        case .cut(let place):
            pickCut(place)
            guard let cut = document.documentCut(at: place) else { return }
            let at = cut.cut.transition.map { cut.atMS - $0.beforeMS + $0.spanMS / 2 } ?? cut.atMS
            documentTimeMS = min(max(0, at), lastDocumentTimeMS)
        case let .fade(clip, end):
            selectLayer(clip)
            guard let layer = document.layer(id: clip), let time = layer.time else { return }
            let length = layer.pictureFadeMS(end)
            let at = end == .in ? time.inMS + length / 2 : time.outMS - length / 2
            documentTimeMS = min(max(0, at), lastDocumentTimeMS)
        }
    }

    // MARK: The rows

    /// **Add Transition ▸** with every kind, Cross dissolve first, putting
    /// the one chosen on `targets`. Never greyed: a place that cannot take a
    /// kind says so in words when it is chosen, which a greyed row cannot.
    func addTransitionMenuRow(_ targets: [TransitionTarget], current: ClipTransitionKind? = nil) -> MenuRow {
        .submenu("Add Transition", ClipTransitionKind.allCases.map { kind -> MenuRow in
            if kind == current { return .toggle(kind.title, isOn: true) {} }
            return .command(kind.title) { self.putTransition(kind, on: targets) }
        })
    }

    /// The clip menu's Add Transition: at both ends of the piece clicked.
    func clipTransitionMenuRows(layerID: UUID, piece index: Int) -> [MenuRow] {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              let targets = document?.transitionTargets(ofClip: layerID, piece: index).map(\.target),
              !targets.isEmpty else { return [] }
        return [addTransitionMenuRow(targets)]
    }

    /// The ruler's and the scrub bar's Add Transition: on the cut nearest the
    /// moment clicked, when one is close enough to mean it.
    func rulerTransitionMenuRows(atMS ms: Int) -> [MenuRow] {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime, let document else { return [] }
        let cut = document.transitionCuts(among: nil)
            .filter { abs($0.atMS - ms) <= clipCutReachMS }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        guard let cut else { return [] }
        return [addTransitionMenuRow([.cut(cut.place)], current: cut.cut.transition?.kind)]
    }

    // MARK: Lit places

    /// The kind whose landing places the timeline is lighting: the tile in
    /// the air over it, else a tile just clicked with no cut picked.
    var transitionSpotsLitKind: ClipTransitionKind? {
        timelineTransitionHover?.kind ?? transitionSpotsFlash
    }

    /// Light every place `kind` could go for a moment: the answer to a tile
    /// clicked with no cut picked is to show where to take it.
    func flashTransitionSpots(_ kind: ClipTransitionKind) {
        transitionSpotsFlashTask?.cancel()
        transitionSpotsFlash = kind
        transitionSpotsFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, self.transitionSpotsFlash == kind else { return }
            self.transitionSpotsFlash = nil
        }
    }
}
