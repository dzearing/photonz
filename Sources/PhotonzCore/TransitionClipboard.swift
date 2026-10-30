import Foundation

// A transition copies from one cut and pastes onto others
// (task `a-transition-can-be-copied-from-one-cut-and-past`).
//
// Premiere's and Final Cut's way: tune a dissolve at one cut, copy it, pick
// another cut (or several clips, or a range) and paste. Each cut gets the same
// kind, length, curve, direction and blur, fitted to what it can pay for the
// way the picker fits a kind (`ClipCut.fitted`): a length the cut cannot pay
// for comes down to the longest it can, and a kind it cannot pay for at all is
// refused with the picker's reason. The transitions mock's panel menu prints
// the row (`video-transitions.html`, `#propMenu`, "Copy transition").
//
// A dip's hold is left behind. A hold is real time put into the edit, and a
// paste that moves everything after a cut would be a surprise nobody asked
// for; the cut it lands on keeps the hold it had.

/// A transition on the clipboard.
public struct CopiedTransition: Hashable, Codable, Sendable {
    public var transition: ClipTransition

    /// What was copied, without its hold.
    public init(_ transition: ClipTransition) {
        var copied = transition
        copied.holdMS = 0
        self.transition = copied
    }

    /// The pasteboard type the app writes it under, so copying anything else
    /// in any app replaces it the way a clipboard should.
    public static let pasteboardType = "com.dzearing.photonz.transition"

    /// What it is, the way the canvas says it: "Cross dissolve, 0.4s".
    public var title: String {
        "\(transition.kind.title), \(ClipTransitionCopy.seconds(transition.lengthMS))"
    }
}

extension ClipCut {

    /// `copied` as it would land on this cut: its kind, curve, direction and
    /// blur as they are, sitting where it sat when real footage here pays for
    /// it, else across the cut, else on whichever side has the most spare,
    /// and the edge frames held for what footage cannot pay
    /// (`ClipCut.placement`). A dip keeps the hold this cut already has. Nil
    /// only where the pieces here are too short to hold it.
    public func fitted(pasting copied: ClipTransition) -> ClipTransition? {
        let kind = copied.kind
        guard let placed = placement(of: kind, lengthMS: copied.lengthMS,
                                     preferring: copied.alignment) else { return nil }
        return ClipTransition(kind: kind, lengthMS: placed.lengthMS, alignment: placed.alignment,
                              holdMS: kind.needsOverlap ? 0 : (transition?.holdMS ?? 0),
                              curve: copied.curve, direction: copied.direction,
                              motionBlur: copied.motionBlur)
    }
}

extension PhotonzDocument {

    /// The transition on the cut at `place`, ready for the clipboard, or nil
    /// where the cut is hard.
    public func copyTransition(at place: TimelineCutPlace) -> CopiedTransition? {
        documentCut(at: place)?.cut.transition.map(CopiedTransition.init)
    }

    /// What pasting `copied` on the cut at `place` would write, or why not.
    /// A cut on a locked track is never touched.
    public func transitionPastePlan(_ copied: CopiedTransition,
                                    on place: TimelineCutPlace) -> TransitionTargetPlan {
        guard let cut = documentCut(at: place), !isOnLockedTrack(place) else {
            return .refused(.noCutNearby)
        }
        guard let fitted = cut.cut.fitted(pasting: copied.transition) else {
            return .refused(.tooShort(copied.transition.kind))
        }
        return .put(fitted, at: place)
    }

    /// Paste `copied` on each of `places`, in the order given, each fitted to
    /// what its cut can pay for. A cut that cannot take it is left exactly as
    /// it was and counted as skipped.
    @discardableResult
    public mutating func pasteTransition(_ copied: CopiedTransition,
                                         on places: [TimelineCutPlace]) -> EveryCutOutcome {
        var outcome = EveryCutOutcome(put: [], skipped: 0)
        for place in places {
            // Read again just before it is written, as every-cut does.
            guard case .put(let transition, _) = transitionPastePlan(copied, on: place) else {
                outcome.skipped += 1
                continue
            }
            if documentCut(at: place)?.cut.transition != transition {
                guard setTransition(transition, at: place) else {
                    outcome.skipped += 1
                    continue
                }
            }
            outcome.put.append(place)
        }
        return outcome
    }

    private func isOnLockedTrack(_ place: TimelineCutPlace) -> Bool {
        let locked = layerIDsOnLockedTracks()
        switch place {
        case let .join(clip, _): return locked.contains(clip)
        case let .edit(outgoing, incoming): return locked.contains(outgoing) || locked.contains(incoming)
        }
    }
}
