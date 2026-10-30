import AppKit
import Foundation
import PhotonzCore

// Copy a transition at one cut, paste it onto others
// (`TransitionClipboard.swift`).
//
// Premiere's and Final Cut's clipboard for a transition: pick the cut, ⌘C,
// pick another cut, ⌘V. No key of its own: Edit ▸ Copy and Paste reach it
// whenever a cut is what is picked, and the cut's right click carries both
// rows. A paste onto several cuts at once goes where ⌘T spreads a transition:
// every cut inside a range drawn on the ruler or on some tracks, or among two
// or more clips picked.
extension EditorState {

    // MARK: Copy

    /// Whether ⌘C means the transition: a cut is picked and has one.
    var canCopyPickedTransition: Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              let place = pickedCutPlace else { return false }
        return document?.copyTransition(at: place) != nil
    }

    /// ⌘C with a cut picked that has a transition: that transition goes on
    /// the clipboard, and the clip does not. False otherwise, so ⌘C copies
    /// what it always did.
    @discardableResult
    func copyPickedTransition() -> Bool {
        guard canCopyPickedTransition, let place = pickedCutPlace else { return false }
        return copyTransition(at: place)
    }

    /// The transition on the cut at `place` onto the clipboard. The canvas
    /// says what was copied, since nothing on screen changes.
    @discardableResult
    func copyTransition(at place: TimelineCutPlace) -> Bool {
        guard Experiments.shared.transitionsAtACutEnabled,
              let copied = document?.copyTransition(at: place),
              let data = try? JSONEncoder().encode(copied) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(CopiedTransition.pasteboardType))
        raiseCanvasNotice(.transitionCopied(copied))
        return true
    }

    /// ⌘X with a cut picked that has a transition: copied, then taken off,
    /// as Premiere cuts a transition picked on the timeline.
    @discardableResult
    func cutPickedTransition() -> Bool {
        guard let place = pickedCutPlace, !isCutPlaceLocked(place),
              copyPickedTransition() else { return false }
        setTransition(nil, at: place)
        return true
    }

    // MARK: Paste

    /// The transition on the clipboard, where the last thing copied was one.
    var transitionOnClipboard: CopiedTransition? {
        guard let data = NSPasteboard.general.data(
            forType: NSPasteboard.PasteboardType(CopiedTransition.pasteboardType)) else { return nil }
        return try? JSONDecoder().decode(CopiedTransition.self, from: data)
    }

    /// The cuts ⌘V puts a copied transition on, in the order ⌘T reads them:
    /// every cut in a range on the ruler, else in a range on some tracks, else
    /// among two or more clips picked; else the cut picked, else the cut the
    /// playhead is standing on. Empty where there is no cut to paste on.
    var transitionPasteTargets: [TimelineCutPlace] {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime, let document else { return [] }
        if rulerRangeHeld != nil, let range = document.markedRangeMS {
            return document.transitionCuts(within: range).map(\.place)
        }
        if let held = trackRangeHeld {
            return document.transitionCuts(within: held.range, onTracks: held.trackIDs).map(\.place)
        }
        if selectedEditPoint == nil, selectedClipCutIndex == nil, actionableLayerIDs.count > 1 {
            let among = document.transitionCuts(among: actionableLayerIDs).map(\.place)
            if !among.isEmpty { return among }
        }
        if let picked = pickedCutPlace { return [picked] }
        let near = document.transitionCuts(among: nil)
            .filter { abs($0.atMS - documentTimeMS) <= clipCutReachMS }
            .min { abs($0.atMS - documentTimeMS) < abs($1.atMS - documentTimeMS) }
        return near.map { [$0.place] } ?? []
    }

    /// ⌘V with a transition on the clipboard: it goes on `place`, or on every
    /// cut `transitionPasteTargets` names, as ONE step to undo. A cut that
    /// cannot pay for it is left as it was and the canvas says why, the way
    /// the picker's tiles do. False where the clipboard holds no transition,
    /// so ⌘V pastes what it always did.
    @discardableResult
    func pasteTransitionOnClipboard(at place: TimelineCutPlace? = nil) -> Bool {
        guard Experiments.shared.transitionsAtACutEnabled, documentHasTime,
              let copied = transitionOnClipboard, var trial = document else { return false }
        let kind = copied.transition.kind
        let targets = place.map { [$0] } ?? transitionPasteTargets
        guard !targets.isEmpty else {
            raiseCanvasNotice(.defaultTransitionRefused(.noCutNearby))
            return true
        }
        let outcome = trial.pasteTransition(copied, on: targets)
        closeTransitionPicker()
        if !outcome.put.isEmpty {
            endTrimBeforeCutting()
            pauseDocument()
            perform { $0.pasteTransition(copied, on: targets) }
        }
        if targets.count == 1, let only = targets.first {
            if outcome.put.isEmpty {
                // The picker's own refusal, and the kind this cut can take.
                let offer = document?.nearestTransition(to: kind, at: only)
                let action: CanvasNoticeAction? = offer.flatMap { $0 == kind ? nil : .putTransition($0, at: only) }
                raiseCanvasNotice(.defaultTransitionRefused(.tooShort(kind)), action: action)
            } else {
                showPastedTransition(at: only)
            }
        } else {
            raiseCanvasNotice(.transitionOnEveryCut(kind, outcome))
        }
        documentMomentChanged()
        return true
    }

    /// Pick the cut that was pasted on and stand half way through it, so the
    /// canvas shows both shots at once.
    private func showPastedTransition(at place: TimelineCutPlace) {
        pickCut(place)
        guard let cut = document?.documentCut(at: place) else { return }
        let at = cut.cut.transition.map { cut.atMS - $0.beforeMS + $0.spanMS / 2 } ?? cut.atMS
        documentTimeMS = min(max(0, at), lastDocumentTimeMS)
    }

    private func isCutPlaceLocked(_ place: TimelineCutPlace) -> Bool {
        switch place {
        case let .join(clip, _): isClipLocked(clip)
        case let .edit(outgoing, incoming): isClipLocked(outgoing) || isClipLocked(incoming)
        }
    }

    // MARK: The rows

    /// Copy Transition and Paste Transition, on the menus of one cut.
    func transitionClipboardMenuRows(at place: TimelineCutPlace, hasTransition: Bool) -> [MenuRow] {
        [
            .command("Copy Transition", KeyClipboardKeys.copy, enabled: hasTransition) {
                self.pickCut(place)
                self.copyTransition(at: place)
            },
            .command("Paste Transition", KeyClipboardKeys.paste, enabled: transitionOnClipboard != nil) {
                self.pasteTransitionOnClipboard(at: place)
            },
        ]
    }
}
