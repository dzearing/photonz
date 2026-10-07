import CoreGraphics
import Foundation

// An edited recording written out by COPYING what it keeps
// (`docs/design/video.md` §8).
//
// The ordinary video export photographs the document at every moment and
// encodes every photograph again, which is right for anything drawn: a box over
// the picture, a zoom, a caption, a dissolve. It is a waste for the commonest
// edit there is. A recording with the fumbles cut out is nothing but stretches
// of the file it came from, and the file already holds those stretches,
// compressed. Copying them across took a three minute Retina recording from
// about seventy five seconds to a second or two.
//
// Two questions, both answered here without a file or a frame:
//
// - **Is this document nothing but cuts?** `copyablePieces(in:)`. It asks the
//   way `untouchedRecording` does, by rebuilding rather than by listing: the
//   recording opened fresh, cut into the same pieces, must be EXACTLY the clip
//   in the document. Anything else at all, however new, is a difference and
//   the document is drawn. Only sound is let through, because sound always
//   goes out through the mix, whichever way the picture is made.
// - **Which frames are copied and which are made again?** `CutCopyPlan`. A
//   compressed frame cannot be copied on its own: most of them are told as a
//   difference from the frames around them, and only a key frame stands alone.
//   So a cut that lands between key frames has the frames from the cut to the
//   next key frame decoded and encoded again, and everything after is copied
//   as it was. A piece that ends between key frames has its last few made again
//   the same way, because their neighbours past the cut are gone.

/// The stretches of one recording an edit keeps, in the order they play.
public struct CopyablePieces: Hashable, Sendable {
    /// The recording they are all stretches of.
    public let movie: MovieRef
    /// Each stretch, in milliseconds of the recording, in play order.
    public let sourceRangesMS: [Range<Int>]

    public init(movie: MovieRef, sourceRangesMS: [Range<Int>]) {
        self.movie = movie
        self.sourceRangesMS = sourceRangesMS
    }

    /// How long they run, back to back.
    public var lengthMS: Int { sourceRangesMS.reduce(0) { $0 + $1.count } }
}

extension PhotonzDocument {

    /// The stretches of the recording this document plays across `span` of
    /// its own clock, where the picture is nothing but stretches of one
    /// recording laid back to back. Nil the moment anything has to be drawn.
    ///
    /// Let through: cuts, trims, pieces carried into another order, and
    /// anything that is only sound (a level, the sound taken off the picture,
    /// music under it), since sound is mixed the same way on either path.
    ///
    /// Not let through: a held frame, a speed, a transition, anything over the
    /// picture, any styling, crop, move or motion on the clip, a canvas that is
    /// not the recording's own size, time past the clip's end, a hidden track.
    public func copyablePieces(in span: Range<Int>) -> CopyablePieces? {
        guard !span.isEmpty else { return nil }
        let pictures = layers.filter { !$0.isSoundOnly }
        guard pictures.count == 1, let clip = pictures.first, let movie = clip.movie,
              let time = clip.time, time.inMS == 0,
              let pieces = clip.clipPieces,
              pieces.pieces.allSatisfy({ !$0.isHeld && $0.speedPercent == ClipPiece.asRecordedPercent
                                          && $0.transitionIn == nil })
        else { return nil }
        if let track = clip.trackID, tracks.contains(where: { $0.id == track && $0.isHidden }) {
            return nil
        }

        // The recording opened fresh and cut the same way, with nothing else.
        var asOpened = PhotonzDocument.recording(movie, name: clip.name, pixelScale: pixelScale)
        guard asOpened.layers.count == 1 else { return nil }
        let plain = ClipPieces(pieces: pieces.pieces.map {
            ClipPiece(sourceInMS: $0.sourceInMS, lengthMS: $0.lengthMS)
        }, sourceLengthMS: pieces.sourceLengthMS)
        asOpened.layers[0].setClipPieces(plain)
        asOpened.durationMS = asOpened.layers[0].time?.outMS
        guard canvasSize == asOpened.canvasSize,
              documentDurationMS == asOpened.documentDurationMS,
              PhotonzDocument.sameShape(Self.pictureOnly(clip, like: asOpened.layers[0]),
                                        asOpened.layers[0])
        else { return nil }

        // Each piece's stretch of the file, kept to the part inside the span.
        var ranges: [Range<Int>] = []
        var start = 0
        for piece in pieces.pieces {
            let end = start + piece.lengthMS
            let from = max(start, span.lowerBound), to = min(end, span.upperBound)
            if from < to {
                let into = piece.sourceInMS + (from - start)
                ranges.append(into..<(into + (to - from)))
            }
            start = end
        }
        guard !ranges.isEmpty else { return nil }
        return CopyablePieces(movie: movie, sourceRangesMS: ranges)
    }

    /// The clip with what only touches its sound, or only says where it sits
    /// in the timeline's rows, set to what `reference` says, so the comparison
    /// is about the picture alone.
    private static func pictureOnly(_ clip: Layer, like reference: Layer) -> Layer {
        var picture = clip
        picture.soundDetached = reference.soundDetached
        picture.soundLevel = reference.soundLevel
        picture.soundTrackID = reference.soundTrackID
        picture.trackID = reference.trackID
        picture.isLocked = reference.isLocked
        return picture
    }
}

/// Which frames of a recording an edit's file copies, which it makes again,
/// and when each one shows in the file.
///
/// Everything is in ticks of one clock, the caller's choice, and every frame
/// is named by where it sits in the file's own DECODE order: the order a
/// decoder reads them in, which is not the order they show in once frames are
/// reordered (an I, then the P it shows two frames later, then the two Bs
/// between them).
public struct CutCopyPlan: Hashable, Sendable {

    /// One frame as the file stores it.
    public struct StoredFrame: Hashable, Sendable {
        /// When it shows.
        public let showsAt: Int64
        /// When it is decoded: never after it shows.
        public let decodesAt: Int64
        /// Whether a decoder can start at it.
        public let isKey: Bool

        public init(showsAt: Int64, decodesAt: Int64, isKey: Bool) {
            self.showsAt = showsAt
            self.decodesAt = decodesAt
            self.isKey = isKey
        }
    }

    /// One frame of the file being written.
    public struct Placed: Hashable, Sendable {
        /// The source frame, by its place in the source's decode order.
        public let index: Int
        /// When it shows in the new file.
        public let showsAt: Int64
        /// When it is decoded in the new file.
        public internal(set) var decodesAt: Int64
        /// How long it shows for.
        public internal(set) var lastsFor: Int64
    }

    /// A stretch of the new file, in the order it is written.
    public enum Run: Hashable, Sendable {
        /// Frames copied as they are, in decode order.
        case copy([Placed])
        /// Frames made again: the source frames `group` (decode order, from a
        /// key frame) are decoded, and the ones listed, in the order they show,
        /// are encoded afresh starting with a key frame of their own.
        case render(group: Range<Int>, frames: [Placed])

        public var frames: [Placed] {
            switch self {
            case .copy(let frames), .render(_, let frames): frames
            }
        }
    }

    /// The runs, in writing order.
    public let runs: [Run]
    /// How long the new file runs.
    public let durationTicks: Int64

    /// Every frame written, in writing order.
    public var placed: [Placed] { runs.flatMap(\.frames) }
    /// How many frames go across untouched.
    public var copiedFrames: Int {
        runs.reduce(0) { if case .copy(let f) = $1 { $0 + f.count } else { $0 } }
    }
    /// How many have to be decoded and encoded again.
    public var renderedFrames: Int {
        runs.reduce(0) { if case .render(_, let f) = $1 { $0 + f.count } else { $0 } }
    }

    /// The plan for writing `pieces` of the file (each a stretch of its show
    /// clock, in play order) back to back from nought.
    ///
    /// Nil where it cannot be done by copying: no frames, nothing kept, a file
    /// that does not open on a key frame, or one whose groups of frames lean
    /// on each other (an "open" group, where a frame after a key frame shows
    /// before it), which cannot be cut at a key frame without breaking.
    public static func make(frames stored: [StoredFrame], pieces: [Range<Int64>]) -> CutCopyPlan? {
        let pieces = pieces.filter { !$0.isEmpty }
        guard !stored.isEmpty, !pieces.isEmpty, stored[0].isKey else { return nil }
        // Only the ORDER of decode times means anything, and a QuickTime file
        // may count them from nought with frames shown before they are
        // decoded on paper. The whole decode clock is slid back until none is.
        let ahead = stored.map { $0.decodesAt - $0.showsAt }.max() ?? 0
        let frames = ahead <= 0 ? stored : stored.map {
            StoredFrame(showsAt: $0.showsAt, decodesAt: $0.decodesAt - ahead, isKey: $0.isKey)
        }

        // The groups: each from a key frame to the next, in decode order.
        var groupOf = [Int](repeating: 0, count: frames.count)
        var groups: [Range<Int>] = []
        var groupStart = 0
        for index in 1...frames.count where index == frames.count || frames[index].isKey {
            groups.append(groupStart..<index)
            for i in groupStart..<index { groupOf[i] = groups.count - 1 }
            groupStart = index
        }
        // Closed groups only: nothing shows before its own key frame, or at or
        // after the next group's.
        for (number, group) in groups.enumerated() {
            let key = frames[group.lowerBound].showsAt
            let next = number + 1 < groups.count ? frames[groups[number + 1].lowerBound].showsAt
                                                 : Int64.max
            guard group.allSatisfy({ frames[$0].showsAt >= key && frames[$0].showsAt < next })
            else { return nil }
        }

        let shown = frames.indices.sorted { frames[$0].showsAt < frames[$1].showsAt }
        var runs: [Run] = []
        var outStart: Int64 = 0
        for piece in pieces {
            let a = piece.lowerBound, b = piece.upperBound
            // The frame on screen at the cut opens the piece; every frame that
            // shows inside it after that keeps its distance from the cut.
            let opening = shown.last { frames[$0].showsAt <= a } ?? shown[0]
            let kept = shown.filter { frames[$0].showsAt >= frames[opening].showsAt
                                      && ($0 == opening || frames[$0].showsAt < b) }
            func placed(_ index: Int) -> Placed {
                Placed(index: index, showsAt: outStart + max(0, frames[index].showsAt - a),
                       decodesAt: 0, lastsFor: 0)
            }
            let shift = outStart - a
            // Walk the groups the piece touches, in order.
            var touched: [Int] = []
            for index in kept where touched.last != groupOf[index] { touched.append(groupOf[index]) }
            let keptSet = Set(kept)
            for number in touched {
                let group = groups[number]
                if group.allSatisfy(keptSet.contains) {
                    runs.append(.copy(group.map { index in
                        var frame = placed(index)
                        frame.decodesAt = frames[index].decodesAt + shift
                        return frame
                    }))
                } else {
                    let drawn = kept.filter { groupOf[$0] == number }.map(placed)
                    runs.append(.render(group: group, frames: drawn))
                }
            }
            outStart += b - a
        }
        return CutCopyPlan(runs: settled(timed(runs, frames: frames), endingAt: outStart),
                           durationTicks: outStart)
    }

    /// Decode times for the frames made again.
    ///
    /// They are encoded without reordering, so each is decoded a fixed lead
    /// ahead of when it shows, and the lead is picked to fit between its
    /// neighbours: after the last frame decoded before it, and before the
    /// first frame of a copied group after it, whose decode times are fixed.
    /// A copied key frame decodes a couple of frames before it shows, so a lead
    /// of nought would leave no room for it; the source's own lead on the key
    /// frame of the group is what is tried first.
    private static func timed(_ runs: [Run], frames: [StoredFrame]) -> [Run] {
        var out: [Run] = []
        var lastDecode = Int64.min
        for (number, run) in runs.enumerated() {
            switch run {
            case .copy(let placed):
                out.append(run)
                lastDecode = placed.last?.decodesAt ?? lastDecode
            case .render(let group, var placed):
                guard let first = placed.first?.showsAt, let last = placed.last?.showsAt else {
                    out.append(run); continue
                }
                let key = frames[group.lowerBound]
                var lead = key.showsAt - key.decodesAt
                // Late enough that the next copied group still decodes after.
                if number + 1 < runs.count, case .copy(let next) = runs[number + 1],
                   let nextDecode = next.first?.decodesAt {
                    lead = max(lead, last - nextDecode + 1)
                }
                // Early enough that it decodes after what came before.
                if lastDecode != .min { lead = min(lead, first - lastDecode - 1) }
                lead = max(0, lead)
                for i in placed.indices { placed[i].decodesAt = placed[i].showsAt - lead }
                out.append(.render(group: group, frames: placed))
                lastDecode = placed.last?.decodesAt ?? lastDecode
            }
        }
        return out
    }

    /// Decode times made to climb, and each frame told how long it shows.
    ///
    /// A copied group keeps its own decode times, which start a few frames
    /// before it shows (that is what reordering costs). Laid after another
    /// piece, those can fall behind the decode times of the frames just
    /// written, so walking back from the end, any frame not decoded before the
    /// one after it is moved earlier until it is. Only the frames right before
    /// a join ever move, and only by the few frames the reordering needs.
    private static func settled(_ runs: [Run], endingAt end: Int64) -> [Run] {
        var all = runs.flatMap(\.frames)
        guard !all.isEmpty else { return runs }
        for position in stride(from: all.count - 2, through: 0, by: -1) {
            all[position].decodesAt = min(all[position].decodesAt, all[position + 1].decodesAt - 1)
        }
        let byShow = all.indices.sorted { all[$0].showsAt < all[$1].showsAt }
        for (rank, position) in byShow.enumerated() {
            let next = rank + 1 < byShow.count ? all[byShow[rank + 1]].showsAt : end
            all[position].lastsFor = max(1, next - all[position].showsAt)
        }
        var rest = all[...]
        return runs.map { run in
            let mine = Array(rest.prefix(run.frames.count))
            rest = rest.dropFirst(run.frames.count)
            switch run {
            case .copy: return .copy(mine)
            case .render(let group, _): return .render(group: group, frames: mine)
            }
        }
    }
}
