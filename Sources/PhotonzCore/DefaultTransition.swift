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
    public func fitted(_ kind: ClipTransitionKind) -> ClipTransition? {
        let longest = longestMS(of: kind)
        guard longest >= ClipTransition.shortestMS else { return nil }
        let asked = transition?.lengthMS ?? ClipTransition.defaultLengthMS
        return ClipTransition(kind: kind, lengthMS: min(max(ClipTransition.shortestMS, asked), longest))
    }
}

/// Why the key put nothing on.
public enum DefaultTransitionRefusal: Hashable, Sendable {
    /// No cut is picked, and none is close enough to the playhead to mean it.
    case noCutNearby
    /// The cut cannot pay for this kind: it needs spare frames either side and
    /// there are none.
    case noSpare(ClipTransitionKind)

    /// The line the canvas says it with.
    public var detail: String {
        switch self {
        case .noCutNearby: "There is no cut at the playhead"
        case .noSpare(let kind): "\(kind.title) needs spare frames either side of this cut"
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
            target = transitionCuts()
                .filter { isFree($0.place) && abs($0.atMS - ms) <= reachMS }
                .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        }
        guard let target else { return .refused(.noCutNearby) }
        guard let transition = target.cut.fitted(kind) else { return .refused(.noSpare(kind)) }
        return .put(transition, at: target.place)
    }
}
