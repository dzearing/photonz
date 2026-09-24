import CoreGraphics
import Foundation

// A transition on the cut between two clips (`docs/design/video-transitions.md`).
//
// A cut inside one clip already carried transitions (`ClipTransitions.swift`).
// This is the cut an editor actually makes: one clip ends on a track and the
// next starts on the same millisecond (`comp-video.html` §02, the edit point).
// Everything that decides what a cut can afford is the same arithmetic, asked
// of the last piece of the outgoing clip and the first piece of the incoming
// one, so the two kinds of cut read, draw and refuse alike.
//
// **Only while the two clips meet.** The transition is written on the arriving
// clip, and it is drawn only while that clip's start is the end of another on
// the same picture track. Part them and nothing is drawn; butt them again and
// it is back, the way a join's transition travels with its piece.

/// Where a cut is: a join between two pieces of one clip, or the edit point
/// between two clips on one track.
public enum TimelineCutPlace: Hashable, Sendable {
    /// Inside one clip, named by the piece that arrives at it.
    case join(clip: UUID, index: Int)
    /// Between two clips, named by the clip that ends and the one that starts.
    case edit(outgoing: UUID, incoming: UUID)

    /// The layer the cut belongs to for picking: the clip itself for a join,
    /// the arriving clip for an edit point.
    public var arrivingClip: UUID {
        switch self {
        case .join(let clip, _): clip
        case .edit(_, let incoming): incoming
        }
    }
}

/// One cut anywhere on the timeline, with what it can afford worked out and
/// the names the panel shows for its two sides.
public struct DocumentCut: Hashable, Sendable {
    public let place: TimelineCutPlace
    /// Where the cut is on the DOCUMENT's clock, the number the ruler shows.
    public let atMS: Int
    /// The arithmetic: spare either side, what is on it, what it can take.
    public let cut: ClipCut
    public let outgoingName: String
    public let incomingName: String
}

extension PhotonzDocument {

    // MARK: - Reading a cut

    /// The cut at a place, or nil where there is none: a join index a clip
    /// does not have, or two clips that do not meet on one picture track.
    public func documentCut(at place: TimelineCutPlace) -> DocumentCut? {
        switch place {
        case let .join(clip, index):
            guard let layer = layer(id: clip), let start = layer.time?.inMS,
                  let cut = layer.clipPieces?.cut(at: index) else { return nil }
            return DocumentCut(place: place, atMS: start + cut.atMS, cut: cut,
                               outgoingName: "Piece \(index)", incomingName: "Piece \(index + 1)")
        case let .edit(outgoing, incoming):
            guard let cut = editPointCut(outgoing: outgoing, incoming: incoming),
                  let out = layer(id: outgoing), let into = layer(id: incoming) else { return nil }
            return DocumentCut(place: place, atMS: cut.atMS, cut: cut,
                               outgoingName: out.name, incomingName: into.name)
        }
    }

    /// The edit point between two clips as a cut: the last piece of the one
    /// going out against the first piece of the one coming in, each with the
    /// recording it still has past its edge. Its `atMS` is on the document's
    /// clock, since the two sides have no clock in common.
    public func editPointCut(outgoing: UUID, incoming: UUID) -> ClipCut? {
        guard let trackID = trackID(ofClip: incoming),
              track(id: trackID)?.kind == .video,
              editPoints(onTrack: trackID).contains(where: {
                  $0.outgoing == outgoing && $0.incoming == incoming
              }),
              let out = layer(id: outgoing), let into = layer(id: incoming),
              let outPieces = out.clipPieces, let inPieces = into.clipPieces,
              let last = outPieces.pieces.last, var first = inPieces.piece(at: 0),
              let at = into.time?.inMS else { return nil }
        first.transitionIn = into.arrivalTransition
        let sameFile = out.movie != nil && out.movie?.id == into.movie?.id
        return ClipCut(index: 0, atMS: at, outgoing: last, incoming: first,
                       spareAfterOutMS: outPieces.trimEndRange(ofPiece: outPieces.count - 1)?.out,
                       spareBeforeInMS: inPieces.trimStartRange(ofPiece: 0)?.out.map { abs($0) },
                       readsOneRecording: sameFile)
    }

    // MARK: - Writing one

    /// Put a transition on a cut, or take one off with nil.
    ///
    /// **Refused rather than shortened**, exactly as a join's is: a length the
    /// cut cannot pay for is the caller's to clamp, with
    /// `ClipCut.longestMS(of:)`, before asking. Nothing moves either way.
    @discardableResult
    public mutating func setTransition(_ transition: ClipTransition?, at place: TimelineCutPlace) -> Bool {
        switch place {
        case let .join(clip, index):
            return setClipTransition(clip, atCut: index, to: transition)
        case let .edit(outgoing, incoming):
            guard let cut = editPointCut(outgoing: outgoing, incoming: incoming) else { return false }
            if let transition {
                guard transition.lengthMS >= ClipTransition.shortestMS,
                      transition.lengthMS <= cut.longestMS(of: transition.kind) else { return false }
            }
            guard transition != cut.transition else { return false }
            updateLayer(id: incoming) { $0.arrivalTransition = transition }
            return true
        }
    }

    // MARK: - What is on screen

    /// Whether any clip carries a transition on the cut it arrives at, which
    /// is nearly never: the one question every frame asks before any of the
    /// work below.
    var hasEditPointTransitions: Bool { layers.contains { $0.arrivalTransition != nil } }

    /// A transition between two clips running at a moment: which clip is on
    /// screen, which one is borrowed beside it, and where in its recording the
    /// borrowed one is reading.
    struct EditPointMoment {
        let onScreen: UUID
        let borrowed: UUID
        let onScreenIsOutgoing: Bool
        let transition: ClipTransition
        let progress: Double
        let dipAmount: Double
        /// Where the borrowed clip reads, running past its own edge into the
        /// spare. Nil for a dip, which borrows nothing, and for a clip with no
        /// recording, which has no frame to read.
        let borrowedSourceMS: Int?
    }

    /// Every transition between two clips running at `ms`. At most one per
    /// clip: a transition may not reach past the middle of either side.
    func editPointMoments(atMS ms: Int) -> [EditPointMoment] {
        var moments: [EditPointMoment] = []
        for incoming in layers where incoming.arrivalTransition != nil {
            guard let start = incoming.time?.inMS,
                  let trackID = trackID(ofClip: incoming.id),
                  let point = editPoints(onTrack: trackID).first(where: { $0.incoming == incoming.id }),
                  let cut = editPointCut(outgoing: point.outgoing, incoming: incoming.id),
                  let drawn = cut.drawnTransition,
                  ms >= start - drawn.beforeMS, ms < start + drawn.afterMS,
                  let outgoing = layer(id: point.outgoing) else { continue }
            let outgoingOnScreen = ms < start
            var source: Int?
            if drawn.kind.needsOverlap {
                source = outgoingOnScreen
                    ? readingOn(incoming, atMS: ms)
                    : readingOn(outgoing, atMS: ms)
            }
            moments.append(EditPointMoment(
                onScreen: outgoingOnScreen ? outgoing.id : incoming.id,
                borrowed: outgoingOnScreen ? incoming.id : outgoing.id,
                onScreenIsOutgoing: outgoingOnScreen, transition: drawn,
                progress: ClipTransition.progress(atMS: ms, cutAtMS: start, drawn),
                dipAmount: ClipTransition.dipAmount(atMS: ms, cutAtMS: start, drawn),
                borrowedSourceMS: source))
        }
        return moments
    }

    /// Where a clip's recording is at a moment it is NOT on screen for, just
    /// either side of its own stretch: its first piece reading early, or its
    /// last running on. Never outside the recording.
    private func readingOn(_ clip: Layer, atMS ms: Int) -> Int? {
        guard clip.movie != nil, let time = clip.time, let pieces = clip.clipPieces else { return nil }
        let index = ms < time.inMS ? 0 : pieces.count - 1
        guard let piece = pieces.piece(at: index) else { return nil }
        let raw = piece.sourceMS(atOffsetMS: ms - time.inMS - pieces.startMS(ofPiece: index),
                                 runningOn: true)
        guard let length = pieces.sourceLengthMS else { return max(0, raw) }
        return min(max(0, raw), length)
    }

    /// The frames the borrowed clips need fetched at a moment.
    func editPointFrameRequests(atMS ms: Int) -> [MovieFrameRequest] {
        editPointMoments(atMS: ms).compactMap { moment in
            guard let source = moment.borrowedSourceMS,
                  let movie = layer(id: moment.borrowed)?.movie else { return nil }
            let frame = movie.frameSourceMS(atSourceMS: source)
            return MovieFrameRequest(layerID: Layer.transitionPartnerID(of: moment.onScreen),
                                     movie: movie, sourceMS: frame,
                                     ref: movie.frameRef(atSourceMS: frame))
        }
    }

    /// `shown` with every transition between two clips running at `ms` drawn
    /// into it: the clip on screen replaced where it stands by the pictures
    /// the transition is made of. `shown` is this document already drawn at
    /// `ms`, so both clips carry their look at that moment.
    func withEditPointTransitionsDrawn(_ shown: PhotonzDocument, atMS ms: Int,
                                       framesInHand: MovieFramesInHand?) -> PhotonzDocument {
        let moments = editPointMoments(atMS: ms)
        guard !moments.isEmpty else { return shown }
        var shown = shown
        for moment in moments {
            guard let index = shown.layers.firstIndex(where: { $0.id == moment.onScreen }),
                  shown.layers[index].isVisible else { continue }
            let onScreen = shown.layers[index]
            if let hex = moment.transition.kind.dipColorHex {
                shown.layers.insert(onScreen.dipPanel(hex: hex, amount: moment.dipAmount), at: index + 1)
                continue
            }
            // Switched off by hand, the borrowed clip is not borrowed.
            guard layer(id: moment.borrowed)?.isVisible == true,
                  let other = shown.layers.first(where: { $0.id == moment.borrowed }) else { continue }
            var content = other.content
            if let source = moment.borrowedSourceMS, let movie = other.movie {
                content = .image(movie.frameRef(atSourceMS: source, holding: framesInHand))
            }
            let borrowed = other.transitionPartner(standingFor: moment.onScreen, showing: content)
            let drawn = moment.onScreenIsOutgoing
                ? Layer.transitionDrawn(moment.transition.kind, progress: moment.progress,
                                        outgoing: onScreen, incoming: borrowed)
                : Layer.transitionDrawn(moment.transition.kind, progress: moment.progress,
                                        outgoing: borrowed, incoming: onScreen)
            shown.layers.replaceSubrange(index...index, with: drawn)
        }
        return shown
    }
}
