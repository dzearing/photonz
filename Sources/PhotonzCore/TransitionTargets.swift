import Foundation

// Where a transition goes when it is asked of a clip, or let go over the
// timeline: where the clips meet.
//
// The user, 2026-10-03: "I expect to right click on a video clip, or on the
// timeline itself, and insert some transition." A cut is one place a
// transition can go. A clip's END is the other: Premiere puts a Cross Dissolve
// on an edge that meets nothing and the picture fades from or to black, and a
// person reaching for a transition at the start of their first clip means
// exactly that. So a transition asked of a clip goes on each of its ends: the
// cut there when something meets it, else a fade (`PictureFade`).
//
// The kinds that only make sense between two pictures (a push, a wipe, a dip
// through white) are refused at an end that meets nothing, with a reason, never
// quietly dropped.

/// One place a transition can go.
public enum TransitionTarget: Hashable, Sendable {
    /// A cut: a join inside a clip, or the edit between two.
    case cut(TimelineCutPlace)
    /// An end of a clip that meets nothing, where a transition is a fade from
    /// or to black.
    case fade(clip: UUID, FadeEnd)
}

/// A target and where it is: the moment on the document's clock and the
/// track it is drawn on.
public struct TransitionSpot: Hashable, Sendable {
    public var target: TransitionTarget
    public var atMS: Int
    public var trackID: UUID?

    public init(target: TransitionTarget, atMS: Int, trackID: UUID?) {
        self.target = target
        self.atMS = atMS
        self.trackID = trackID
    }
}

/// What putting one kind on one target would do.
public enum TransitionTargetPlan: Hashable, Sendable {
    case put(ClipTransition, at: TimelineCutPlace)
    case fade(clip: UUID, FadeEnd, lengthMS: Int)
    case refused(DefaultTransitionRefusal)

    /// How long a transition at an end that meets nothing fades over: a
    /// second, the fade keys' length and Premiere's and Final Cut's default.
    public static let fadeLengthMS = 1000

    public var lands: Bool {
        if case .refused = self { return false }
        return true
    }
}

/// What one kind asked of several targets did.
public struct TransitionTargetOutcome: Hashable, Sendable {
    public var put: [TransitionTarget]
    public var refused: [DefaultTransitionRefusal]

    public init(put: [TransitionTarget] = [], refused: [DefaultTransitionRefusal] = []) {
        self.put = put
        self.refused = refused
    }
}

extension ClipTransitionKind {

    /// Whether this kind means something at an end of a clip that meets
    /// nothing: a dissolve from nothing, and a dip to black, are the picture
    /// rising out of black.
    public var fadesAtAFreeEnd: Bool { self == .dissolve || self == .dipToBlack }
}

extension PhotonzDocument {

    /// The two ends of one piece of a clip, start first, as a transition sees
    /// them: the join inside the clip, the edit with the clip that meets it on
    /// its track, or, at an end of a recording that meets nothing, a fade.
    /// Empty for a clip on a locked track, and for anything that is not a
    /// recording.
    public func transitionTargets(ofClip id: UUID, piece index: Int) -> [TransitionSpot] {
        guard let layer = layer(id: id), layer.movie != nil, let time = layer.time,
              let pieces = layer.clipPieces, index >= 0, index < pieces.count,
              !layerIDsOnLockedTracks().contains(id) else { return [] }
        let track = trackID(ofClip: id)
        let edits = track.map { editPoints(onTrack: $0) } ?? []
        var spots: [TransitionSpot] = []
        // Its start.
        if index > 0 {
            spots += spot(.cut(.join(clip: id, index: index)), track: track)
        } else if let edit = edits.first(where: { $0.incoming == id }) {
            spots += spot(.cut(.edit(outgoing: edit.outgoing, incoming: id)), track: track)
        } else if layer.canFadePicture {
            spots.append(TransitionSpot(target: .fade(clip: id, .in), atMS: time.inMS, trackID: track))
        }
        // Its end.
        if index < pieces.count - 1 {
            spots += spot(.cut(.join(clip: id, index: index + 1)), track: track)
        } else if let edit = edits.first(where: { $0.outgoing == id }) {
            spots += spot(.cut(.edit(outgoing: id, incoming: edit.incoming)), track: track)
        } else if layer.canFadePicture {
            spots.append(TransitionSpot(target: .fade(clip: id, .out), atMS: time.outMS, trackID: track))
        }
        return spots
    }

    private func spot(_ target: TransitionTarget, track: UUID?) -> [TransitionSpot] {
        guard case .cut(let place) = target, let cut = documentCut(at: place) else { return [] }
        return [TransitionSpot(target: target, atMS: cut.atMS, trackID: track)]
    }

    /// Every place a transition tile can land, in time order: each cut
    /// (`transitionCuts`), and each end of a recording that meets nothing.
    /// Nothing on a locked track.
    public func transitionSpots() -> [TransitionSpot] {
        var spots = transitionCuts(among: nil).map { cut in
            TransitionSpot(target: .cut(cut.place), atMS: cut.atMS, trackID: trackID(ofClip: cut.place.arrivingClip))
        }
        for layer in timelineClipLayers where layer.movie != nil {
            let count = layer.clipPieces?.count ?? 1
            let ends = transitionTargets(ofClip: layer.id, piece: 0) + transitionTargets(ofClip: layer.id, piece: count - 1)
            for end in ends {
                if case .fade = end.target, !spots.contains(end) { spots.append(end) }
            }
        }
        return spots.sorted { $0.atMS < $1.atMS }
    }

    /// The place a tile let go at `ms` lands: the nearest spot on `track`, no
    /// further than `reachMS` away. With no track, which is the pointer
    /// between two, a spot on any track will do.
    public func transitionDropSpot(atMS ms: Int, onTrack track: UUID?, reachMS: Int) -> TransitionSpot? {
        transitionSpots()
            .filter { abs($0.atMS - ms) <= reachMS && (track == nil || $0.trackID == track) }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
    }

    /// What putting `kind` on `target` would do.
    public func transitionPlan(_ kind: ClipTransitionKind, on target: TransitionTarget) -> TransitionTargetPlan {
        switch target {
        case .cut(let place):
            guard let cut = documentCut(at: place) else { return .refused(.noCutNearby) }
            guard let transition = cut.cut.fitted(kind) else { return .refused(.noSpare(kind)) }
            return .put(transition, at: place)
        case let .fade(clip, end):
            guard kind.fadesAtAFreeEnd else { return .refused(.needsTwoClips(kind)) }
            guard let layer = layer(id: clip) else { return .refused(.noCutNearby) }
            let now = layer.pictureFadeMS(end)
            if now > 0 { return .fade(clip: clip, end, lengthMS: now) }
            let fits = ([TransitionTargetPlan.fadeLengthMS] + PictureFade.stopsMS.reversed())
                .first { $0 > 0 && $0 <= TransitionTargetPlan.fadeLengthMS && layer.canSetPictureFade(end, toMS: $0) }
            guard let fits else { return .refused(.noSpare(kind)) }
            return .fade(clip: clip, end, lengthMS: fits)
        }
    }

    /// Put `kind` on each of `targets`, each fitted to what it can take. A
    /// target that cannot take it is left exactly as it was, and its reason
    /// is counted.
    @discardableResult
    public mutating func putTransition(_ kind: ClipTransitionKind, on targets: [TransitionTarget])
        -> TransitionTargetOutcome {
        var outcome = TransitionTargetOutcome()
        for target in targets {
            switch transitionPlan(kind, on: target) {
            case .put(_, let place):
                // Read again just before it is written: a dip that holds puts
                // real time in and moves everything after it.
                if putTransition(kind, onEvery: [place]).put.isEmpty {
                    outcome.refused.append(.noSpare(kind))
                } else {
                    outcome.put.append(target)
                }
            case let .fade(clip, end, length):
                if layer(id: clip)?.pictureFadeMS(end) != length { setPictureFade(clip, end, toMS: length) }
                outcome.put.append(target)
            case .refused(let why):
                outcome.refused.append(why)
            }
        }
        return outcome
    }

    /// The kind to offer when `kind` cannot go on the cut at `place`: `kind`
    /// itself where it fits, else a dip to black, which spends no spare frames
    /// and so always fits.
    public func nearestTransition(to kind: ClipTransitionKind, at place: TimelineCutPlace) -> ClipTransitionKind? {
        guard let cut = documentCut(at: place)?.cut else { return nil }
        if cut.fitted(kind) != nil { return kind }
        return [ClipTransitionKind.dipToBlack, .dipToWhite].first { cut.fitted($0) != nil }
    }
}
