import Foundation

// The two pictures a cut's transition tiles play between
// (`video-transition-wt.html`, "At this cut").
//
// The user, 2026-10-29: picking how one clip becomes the next happens at the
// cut, from tiles that preview with the two real clips, so the person sees
// what they get before they choose. A tile turns the last frame of the clip
// going out into the first frame of the one coming in; this says which frame
// of which recording each of those is. The app fetches the pictures.

/// The frame either side of a cut: what the outgoing clip shows as it ends,
/// and what the incoming one shows as it starts. A side with no recording
/// behind it (a title, a shape) has none, and its tile draws a stand-in.
public struct CutShots: Hashable, Sendable {

    /// One frame of one recording.
    public struct Shot: Hashable, Sendable {
        public let movie: MovieRef
        /// Where in the file the frame is.
        public let sourceMS: Int
    }

    public let outgoing: Shot?
    public let incoming: Shot?
}

extension PhotonzDocument {

    /// The frames either side of the cut at `place`, or nil where there is no
    /// cut. The outgoing side is a millisecond before its end, which decodes
    /// as its last frame; the incoming side is its first.
    public func cutShots(at place: TimelineCutPlace) -> CutShots? {
        guard let cut = documentCut(at: place)?.cut else { return nil }
        let movies: (out: MovieRef?, into: MovieRef?) = switch place {
        case let .join(clip, _): (layer(id: clip)?.movie, layer(id: clip)?.movie)
        case let .edit(outgoing, incoming): (layer(id: outgoing)?.movie, layer(id: incoming)?.movie)
        }
        let last = cut.outgoing.sourceMS(atOffsetMS: max(0, cut.outgoing.lengthMS - 1))
        let first = cut.incoming.sourceMS(atOffsetMS: 0)
        return CutShots(outgoing: movies.out.map { CutShots.Shot(movie: $0, sourceMS: last) },
                        incoming: movies.into.map { CutShots.Shot(movie: $0, sourceMS: first) })
    }
}

extension ClipTransitionCopy {

    /// What a kind does at a cut, said about both clips: "Cube: take turns
    /// into b-roll". Inside one clip both sides are that clip, so it says it
    /// is the cut inside it. Never what one clip does on its own.
    public static func between(_ kind: ClipTransitionKind, at cut: DocumentCut) -> String {
        if case .join = cut.place { return "\(kind.title) at the cut inside \(cut.outgoingName)" }
        return "\(kind.title): \(cut.outgoingName) turns into \(cut.incomingName)"
    }

    /// The two sides along the top of the tiles, outgoing first. A cut
    /// inside one clip is named by the clip and where the cut is.
    public static func sides(_ cut: DocumentCut) -> String {
        if case .join = cut.place { return "\(cut.outgoingName), at \(CaptionProgress.clock(cut.atMS))" }
        return "\(cut.outgoingName) \u{2192} \(cut.incomingName)"
    }
}
