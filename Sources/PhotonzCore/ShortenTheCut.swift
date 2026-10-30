import Foundation

// Shortening a cut to pay for an overlap (`video-transition-wt.html` step 10,
// "Or · Shorten the cut by 1.0s").
//
// An overlap is paid for with spare media, never with position
// (`ClipTransitions.swift`). A cut with no spare either side, which is what a
// second clip dropped at full length after a recording used to its last frame
// leaves, holds its edge frames for the transition instead (the user,
// 2026-10-29). Final Cut's other answer is to overlap the clips and make the
// project shorter, so the transition plays real footage; the mock's is the
// same edit, OFFERED rather than taken, because it moves the incoming clip and
// everything after it.
//
// **What it costs is exactly the frames the overlap needs.** The overlap sits
// across the cut, so half of it is read past the outgoing clip's end and half
// before the incoming one's start. Whatever spare a side already has is spent
// first; the rest is trimmed off that side's end, which makes those frames
// spare. The stretch trimmed is taken out of every unlocked track and the gap
// closes (`extractStretch`, Premiere's Extract with sync lock on), so the
// captions, titles and music after the cut stay in step with the picture.

/// What shortening a cut would take: the transition it pays for, and how much
/// comes off each side of the cut.
public struct ClipCutShortening: Hashable, Sendable {
    /// What goes on the cut once it is paid for: across it, with no hold.
    public let transition: ClipTransition
    /// How much comes off the end of the outgoing side.
    public let fromOutgoingMS: Int
    /// How much comes off the start of the incoming side.
    public let fromIncomingMS: Int

    /// How much shorter the cut, and the timeline after it, gets.
    public var totalMS: Int { fromOutgoingMS + fromIncomingMS }
}

extension ClipCut {

    /// What shortening this cut would take to pay for `kind`, `lengthMS` long
    /// (the kind's usual length when nil), with real footage and no frame
    /// held. Nil where nothing needs paying for (a dip, or a cut whose spare
    /// pays for it wherever it sits) and where a side is too short to give up
    /// the frames and still hold the overlap.
    public func shortening(for kind: ClipTransitionKind, lengthMS: Int? = nil) -> ClipCutShortening? {
        shortening(for: ClipTransition(kind: kind, lengthMS: lengthMS))
    }

    /// The same for one transition, kept as it is but placed across the cut.
    public func shortening(for asked: ClipTransition) -> ClipCutShortening? {
        guard asked.kind.needsOverlap,
              !ClipTransitionAlignment.allCases.contains(where: {
                  footageMS(of: asked.kind, aligned: $0) >= asked.lengthMS
              }) else { return nil }
        var transition = asked
        transition.alignment = .across
        transition.holdMS = 0
        // A side nothing stops (a held frame) lends whatever it is asked for.
        let fromOutgoing = spareAfterOutMS.map { max(0, transition.afterMS - $0) } ?? 0
        let fromIncoming = spareBeforeInMS.map { max(0, transition.beforeMS - $0) } ?? 0
        // What is left of each side still has to reach past the middle of the
        // overlap (`longestMS(of:aligned:)`).
        guard outgoing.lengthMS - fromOutgoing >= transition.lengthMS,
              incoming.lengthMS - fromIncoming >= transition.lengthMS else { return nil }
        return ClipCutShortening(transition: transition, fromOutgoingMS: fromOutgoing,
                                 fromIncomingMS: fromIncoming)
    }

    /// What Properties offers at a cut whose transition holds edge frames:
    /// the same transition, at its length, played on real footage. Nothing
    /// where the transition there holds none, or where there is none.
    public func shorteningOffer(defaultKind: ClipTransitionKind) -> ClipCutShortening? {
        guard holdsFrames, let asked = drawnTransition else { return nil }
        return shortening(for: asked)
    }
}

extension PhotonzDocument {

    /// What shortening the cut at `place` would take to pay for `kind`, or nil
    /// where it cannot be done: there is nothing to pay for, a side is too
    /// short, or a clip at the cut is locked.
    public func cutShortening(for kind: ClipTransitionKind, at place: TimelineCutPlace) -> ClipCutShortening? {
        guard let shortening = documentCut(at: place)?.cut.shortening(for: kind) else { return nil }
        var trial = self
        return trial.shortenCut(shortening, at: place) == nil ? nil : shortening
    }

    /// Shorten the cut at `place` to pay for `kind` and put it on. Answers
    /// where the cut is afterwards, or nil where nothing changed.
    @discardableResult
    public mutating func shortenCut(for kind: ClipTransitionKind, at place: TimelineCutPlace) -> TimelineCutPlace? {
        guard let shortening = documentCut(at: place)?.cut.shortening(for: kind) else { return nil }
        return shortenCut(shortening, at: place)
    }

    /// Take `shortening.totalMS` out of the timeline at the cut, the frames
    /// either side of it that the overlap needs, and put the transition on.
    /// All of it or none of it: one edit, so one undo puts the cut back.
    @discardableResult
    public mutating func shortenCut(_ shortening: ClipCutShortening,
                                    at place: TimelineCutPlace) -> TimelineCutPlace? {
        let clips: [UUID] = switch place {
        case let .join(clip, _): [clip]
        case let .edit(outgoing, incoming): [outgoing, incoming]
        }
        // A locked clip or track is not trimmed, and a cut half shortened is
        // worse than one left alone.
        let locked = layerIDsOnLockedTracks()
        guard !clips.contains(where: { locked.contains($0) || layer(id: $0)?.isLocked != false }) else {
            return nil
        }
        var trial = self
        // A dip holding on its colour is a gap between the two clips; it goes
        // first, so the clips meet and the trim lands on their ends.
        if (trial.documentCut(at: place)?.cut.transition?.holdMS ?? 0) > 0 {
            trial.setTransition(nil, at: place)
        }
        guard let at = trial.documentCut(at: place)?.atMS else { return nil }
        let from = at - shortening.fromOutgoingMS
        let to = at + shortening.fromIncomingMS
        guard trial.extractStretch(fromMS: from, toMS: to) else { return nil }
        // Markers and the In and Out go with the picture they were put on.
        let squeeze = { (ms: Int) -> Int in ms <= from ? ms : (ms >= to ? ms - (to - from) : from) }
        trial.moveMarkers(squeeze)
        trial.markInMS = trial.markInMS.map(squeeze)
        trial.markOutMS = trial.markOutMS.map(squeeze)
        if let markIn = trial.markInMS, let markOut = trial.markOutMS, markOut <= markIn { trial.clearMarkInOut() }
        // The cut may already wear exactly this transition, holding the frames
        // it now plays for real: that is it on, not a refusal.
        guard let cut = trial.documentCut(at: place)?.cut,
              shortening.transition.lengthMS <= cut.longestMS(for: shortening.transition),
              cut.transition == shortening.transition
                || trial.setTransition(shortening.transition, at: place) else { return nil }
        self = trial
        return place
    }
}

extension ClipTransitionCopy {

    /// The button that offers it (`#btnShorten`).
    public static func shortenTheCut(_ shortening: ClipCutShortening) -> String {
        "Shorten the cut by \(seconds(shortening.totalMS))"
    }

    /// The button's tip: what it puts on the cut.
    public static func shorteningTip(_ shortening: ClipCutShortening) -> String {
        "\(shortening.transition.kind.title), \(seconds(shortening.transition.lengthMS))"
    }

    /// The button's own sentence, behind the line above it: what shortening
    /// does instead of holding the edge frames.
    public static func shorteningHelp(_ shortening: ClipCutShortening, incomingName: String) -> String {
        "Shortening the cut by \(seconds(shortening.totalMS)) plays real footage through the "
            + "\(shortening.transition.kind.title.lowercased()) instead of held frames. It moves "
            + "\(incomingName) and everything after it, so it is offered rather than taken."
    }
}
