import Foundation
import PhotonzCore

// Putting a transition where the clips meet (`TransitionTargets.swift`): from
// a tile let go over the timeline and a tile clicked in the panel. A right
// click on a clip, a cut or the ruler opens the tiles at the cut instead
// (`transitionPickerMenuRow`). Every door comes through `putTransition`, so each
// says the same thing when a place cannot take what was asked, and offers what
// it can take.
extension EditorState {

    /// Put `kind` on each of `targets` as ONE step to undo: a cut gets the
    /// transition, holding edge frames where its footage runs out, and an end
    /// of a clip that meets nothing fades. Why nothing went on is said on the
    /// canvas, and a cut too short for it is offered the kind it can take; a
    /// free end that could not take it beside a cut that did is not news.
    /// False where nothing went on.
    @discardableResult
    func putTransition(_ kind: ClipTransitionKind, on targets: [TransitionTarget]) -> Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              var trial = document, !targets.isEmpty else { return false }
        let starved = targets.compactMap { target -> TimelineCutPlace? in
            guard case .cut(let place) = target,
                  case .refused(.tooShort) = trial.transitionPlan(kind, on: target) else { return nil }
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
                raiseCanvasNotice(.defaultTransitionRefused(.tooShort(kind)), action: action)
            }
        } else if let why = outcome.headline {
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

    /// **Transition…**: the tiles at one cut (`TransitionPicker`), the same
    /// ones a click on the cut opens. Opened a pass after the menu that asked
    /// for them has gone, since a popover asked for while a menu is still
    /// closing does not open.
    func transitionPickerMenuRow(at place: TimelineCutPlace,
                                 title: String = TimelineMenuTable.title(.transition, playheadMS: 0) ?? "") -> MenuRow {
        .command(title) { self.openTransitionPickerAfterMenu(at: place) }
    }

    func openTransitionPickerAfterMenu(at place: TimelineCutPlace) {
        Task { @MainActor [weak self] in
            await NextRunLoopPass.start()
            self?.openTransitionPicker(at: place)
        }
    }

    /// The clip menu's one row about where it meets another clip: Transition…
    /// at the one cut it has, or, where it meets clips at both ends, At the
    /// Start… and At the End… under Transition. Nothing at an end that meets
    /// nothing: that end fades by its handle on the bar.
    func clipTransitionMenuRows(layerID: UUID, piece index: Int) -> [MenuRow] {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              let spots = document?.transitionTargets(ofClip: layerID, piece: index) else { return [] }
        let ends = spots.compactMap { spot -> (start: Bool, place: TimelineCutPlace)? in
            guard case .cut(let place) = spot.target else { return nil }
            // The cut the piece arrives at: the join before it, or the edit
            // where this clip comes in.
            let start = switch place {
            case let .join(_, cut): cut == index
            case let .edit(_, incoming): incoming == layerID
            }
            return (start: start, place: place)
        }
        guard let only = ends.first else { return [] }
        guard ends.count > 1 else { return [transitionPickerMenuRow(at: only.place)] }
        return [.submenu("Transition", ends.map { end in
            transitionPickerMenuRow(at: end.place, title: end.start ? "At the Start\u{2026}" : "At the End\u{2026}")
        })]
    }

    /// The ruler's and the scrub bar's Transition…: the tiles at the cut
    /// nearest the moment clicked, when one is close enough to mean it.
    func rulerTransitionMenuRows(atMS ms: Int) -> [MenuRow] {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime, let document else { return [] }
        let cut = document.transitionCuts(among: nil)
            .filter { abs($0.atMS - ms) <= clipCutReachMS }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        guard let cut else { return [] }
        return [transitionPickerMenuRow(at: cut.place)]
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
