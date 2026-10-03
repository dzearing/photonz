import Foundation

// One key puts the usual transition on the cut at the playhead.
//
// Premiere's ⌘D and Final Cut's ⌘T: stand on a cut, press the key, and the
// default transition is on it, without a click on the cut or a pick from the
// tiles. ⌘D is Photoshop's Deselect here and the app follows Photoshop for the
// keys a picture uses, so the key is Final Cut's ⌘T, which nothing else in the
// app wanted (`TimelineKeys`).
//
// Everything here is the decision: which cut, what goes on it, and when the
// answer is no. The app turns the answer into one step to undo.

extension ClipTransitionKind {

    /// What the key puts on a cut until somebody picks another: Premiere's and
    /// Final Cut's own default.
    public static let usualDefault: ClipTransitionKind = .dissolve

    /// The default read back off disk. Anything that is not a kind, including
    /// nothing at all, is the usual one: a setting that went missing is not a
    /// reason for the key to stop working.
    public init(storedDefault raw: String?) {
        self = raw.flatMap(ClipTransitionKind.init(rawValue:)) ?? .usualDefault
    }
}

extension ClipCut {

    /// The transition putting `kind` on this cut would write: the length that
    /// is there now, else the usual length, never longer than this cut can pay
    /// for. Nil where it cannot take `kind` at all.
    ///
    /// It sits where the one there now sits when that side can pay, else
    /// across the cut, else on whichever side has the spare: a clip dropped
    /// from its first frame has nothing before its in point, and Premiere puts
    /// a dissolve there after the cut rather than refusing it. A dip keeps the
    /// hold the cut has; anything else holds nothing.
    public func fitted(_ kind: ClipTransitionKind) -> ClipTransition? {
        let asked = transition?.lengthMS ?? ClipTransition.defaultLengthMS
        let hold = kind.needsOverlap ? 0 : (transition?.holdMS ?? 0)
        var order: [ClipTransitionAlignment] = [transition?.alignment ?? .across, .across]
        order += ClipTransitionAlignment.allCases
            .filter { !order.contains($0) }
            .sorted { longestMS(of: kind, aligned: $0) > longestMS(of: kind, aligned: $1) }
        for alignment in order {
            let longest = longestMS(of: kind, aligned: alignment)
            guard longest >= ClipTransition.shortestMS else { continue }
            return ClipTransition(kind: kind, lengthMS: min(max(ClipTransition.shortestMS, asked), longest),
                                  alignment: alignment, holdMS: hold)
        }
        return nil
    }
}

/// Why the key put nothing on.
public enum DefaultTransitionRefusal: Hashable, Sendable {
    /// No cut is picked, and none is close enough to the playhead to mean it.
    case noCutNearby
    /// The cut cannot pay for this kind: it needs spare frames either side and
    /// there are none.
    case noSpare(ClipTransitionKind)
    /// The end of a clip that meets nothing, and a kind that only means
    /// something between two pictures (`TransitionTargets.swift`).
    case needsTwoClips(ClipTransitionKind)

    /// The line the canvas says it with.
    public var detail: String {
        switch self {
        case .noCutNearby: "There is no cut at the playhead"
        case .noSpare(let kind): "\(kind.title) needs spare frames either side of this cut"
        case .needsTwoClips(let kind): "\(kind.title) needs a clip on both sides"
        }
    }
}

/// What the key will do.
public enum DefaultTransitionPlan: Hashable, Sendable {
    case put(ClipTransition, at: TimelineCutPlace)
    case refused(DefaultTransitionRefusal)
}

extension PhotonzDocument {

    /// Every cut a transition can go on, in time order: each join inside a
    /// clip that plays a recording, and each edit point between two clips on
    /// a picture track. A clip of sound alone has cuts too, but nothing is
    /// drawn across them, so they are not offered.
    public func transitionCuts() -> [DocumentCut] {
        var places: [TimelineCutPlace] = []
        for layer in timelineClipLayers where layer.movie != nil {
            for cut in layer.clipCuts { places.append(.join(clip: layer.id, index: cut.index)) }
        }
        for track in timelineTracks where track.kind == .video {
            for point in editPoints(onTrack: track.id) {
                places.append(.edit(outgoing: point.outgoing, incoming: point.incoming))
            }
        }
        return places.compactMap { documentCut(at: $0) }.sorted { $0.atMS < $1.atMS }
    }

    /// What the key does: put `kind` on the cut that is `picked`, else on the
    /// cut nearest `ms` no further than `reachMS` away. A cut on a locked
    /// track is never touched, picked or not.
    ///
    /// The distance is on it for the reason the panel has one
    /// (`EditorState.clipCutReachMS`): the nearest cut in a recording with one
    /// join may be four seconds from where anybody is looking.
    public func defaultTransitionPlan(_ kind: ClipTransitionKind, picked: TimelineCutPlace?,
                                      atMS ms: Int, reachMS: Int) -> DefaultTransitionPlan {
        let locked = layerIDsOnLockedTracks()
        func isFree(_ place: TimelineCutPlace) -> Bool {
            switch place {
            case let .join(clip, _): !locked.contains(clip)
            case let .edit(outgoing, incoming): !locked.contains(outgoing) && !locked.contains(incoming)
            }
        }
        let target: DocumentCut?
        if let picked, let cut = documentCut(at: picked) {
            target = isFree(picked) ? cut : nil
        } else {
            target = transitionCuts(among: nil)
                .filter { abs($0.atMS - ms) <= reachMS }
                .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        }
        return Self.plan(kind, on: target)
    }

    /// A transition tile let go over the timeline: `kind` on the cut nearest
    /// `ms` on `track`, no further than `reachMS` away, the way Premiere takes
    /// a transition dragged out of its Effects panel onto an edit point. With
    /// no track, which is the pointer between two, any picture track's cut in
    /// reach will do. A cut on a locked track is never touched.
    public func transitionDropPlan(_ kind: ClipTransitionKind, atMS ms: Int, onTrack track: UUID?,
                                   reachMS: Int) -> DefaultTransitionPlan {
        let target = transitionCuts(among: nil)
            .filter { cut in
                abs(cut.atMS - ms) <= reachMS
                    && (track.map { trackID(ofClip: cut.place.arrivingClip) == $0 } ?? true)
            }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        return Self.plan(kind, on: target)
    }

    private static func plan(_ kind: ClipTransitionKind, on target: DocumentCut?) -> DefaultTransitionPlan {
        guard let target else { return .refused(.noCutNearby) }
        guard let transition = target.cut.fitted(kind) else { return .refused(.noSpare(kind)) }
        return .put(transition, at: target.place)
    }
}

// MARK: - Every cut at once

/// What one transition put on every cut did: the cuts it went on, in time
/// order, and how many it could not go on because they have no spare frames
/// to pay for it. The mock's Apply to every cut, and Premiere's Apply Default
/// Transitions to Selection.
public struct EveryCutOutcome: Hashable, Sendable {
    public var put: [TimelineCutPlace]
    public var skipped: Int

    public init(put: [TimelineCutPlace], skipped: Int) {
        self.put = put
        self.skipped = skipped
    }

    /// The line the canvas says it with: how many took it, and how many were
    /// left as they were.
    public var countLine: String {
        guard !put.isEmpty else {
            switch skipped {
            case 0: return "There are no cuts"
            case 1: return "1 cut has no spare frames"
            default: return "\(skipped) cuts have no spare frames"
            }
        }
        let on = put.count == 1 ? "On 1 cut" : "On \(put.count) cuts"
        return skipped == 0 ? on : "\(on), \(skipped) skipped"
    }
}

extension PhotonzDocument {

    /// The cuts a transition can go on, leaving out any on a locked track.
    /// With `clips`, only the joins inside those clips and the edit points
    /// where BOTH sides are among them: Premiere's selection, never the edit
    /// to a clip nobody picked.
    public func transitionCuts(among clips: Set<UUID>? = nil) -> [DocumentCut] {
        let locked = layerIDsOnLockedTracks()
        return transitionCuts().filter { cut in
            switch cut.place {
            case let .join(clip, _):
                !locked.contains(clip) && (clips?.contains(clip) ?? true)
            case let .edit(outgoing, incoming):
                !locked.contains(outgoing) && !locked.contains(incoming)
                    && (clips.map { $0.contains(outgoing) && $0.contains(incoming) } ?? true)
            }
        }
    }

    /// Put `kind` on every cut, or every cut among `clips`, each fitted to
    /// what that cut can pay for (`ClipCut.fitted`). A cut that cannot pay is
    /// left exactly as it was and counted as skipped.
    ///
    /// Each cut is read again just before it is written, because a dip that
    /// holds on black puts real time in and moves everything after it.
    @discardableResult
    public mutating func putTransitionOnEveryCut(_ kind: ClipTransitionKind,
                                                 among clips: Set<UUID>? = nil) -> EveryCutOutcome {
        putTransition(kind, onEvery: transitionCuts(among: clips).map(\.place))
    }

    /// `kind` on each of `places`, in the order given, each fitted to what
    /// its cut can pay for.
    mutating func putTransition(_ kind: ClipTransitionKind,
                                onEvery places: [TimelineCutPlace]) -> EveryCutOutcome {
        var outcome = EveryCutOutcome(put: [], skipped: 0)
        for place in places {
            let cut = documentCut(at: place)?.cut
            guard let transition = cut?.fitted(kind) else {
                outcome.skipped += 1
                continue
            }
            // Already wearing exactly this: it is on, whatever writing it
            // again would say, and it has spare to pay for it.
            guard cut?.transition != transition else {
                outcome.put.append(place)
                continue
            }
            guard setTransition(transition, at: place) else {
                outcome.skipped += 1
                continue
            }
            outcome.put.append(place)
        }
        return outcome
    }
}
