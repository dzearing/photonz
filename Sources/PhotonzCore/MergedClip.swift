import CoreGraphics
import Foundation

// A stretch of a track merged into one clip, and broken apart again
// (`merge-a-range-into-one-clip-and-break-it-apart-a`).
//
// Premiere nests a sequence and Final Cut makes a compound clip. Here a range
// drawn on the ruler is right clicked, Merge into One Clip, and on every track
// the clips under it become ONE clip that plays and sounds exactly as they did.
//
// **A merged clip is a clip whose recording is a little timeline.** It holds
// the clips it covers, WHOLE, on a clock of their own, and it reads that clock
// the way a clip reads its file: `LayerTime.sourceInMS` is where on the inner
// clock it starts, and the clips' media either side of the range is its spare.
// So every edit a clip already has works on it unchanged: a move slides the
// window, a trim opens or closes it, a split cuts it into pieces, and a
// transition on the cut it arrives at is paid for out of that spare.
//
// **Nothing inside is reachable from outside.** The clips it holds are not the
// layers list's children and no walk over the document meets them, so nothing
// that edits the outer timeline (a ripple, a lift, a landing) can move them by
// mistake on the wrong clock. They come out only three ways: drawn at a moment
// (`drawn(atTimeMS:)`), fetched (`movieFrames`), heard (`audioMix`), and taken
// back out by Break Apart.

/// What a merged clip holds.
public struct MergedClip: Hashable, Codable, Sendable {

    /// What a merged clip is called when it is made, the name Final Cut gives a
    /// compound clip, in the words of the menu row that makes one.
    public static let defaultName = "Merged Clip"

    /// The clips, back to front, on the merged clip's own clock: nought is
    /// where the first of them starts.
    public internal(set) var layers: [Layer]
    /// The track they sat on, with its switches off, so the cuts between them
    /// are still cuts and a transition on one is still drawn.
    public internal(set) var track: DocumentTrack
    /// How long the inner clock runs: from the first of the clips starting to
    /// the last of them ending.
    public internal(set) var lengthMS: Int

    public init(layers: [Layer], track: DocumentTrack, lengthMS: Int) {
        self.layers = layers
        self.track = DocumentTrack(id: track.id, name: track.name, kind: track.kind)
        self.lengthMS = max(LayerTime.shortestMS, lengthMS)
    }

    /// The clips as a document of their own, which is how they are drawn,
    /// fetched and heard: a document already knows how to do all three.
    func document(canvasSize: CGSize, pixelScale: CGFloat) -> PhotonzDocument {
        var inner = PhotonzDocument(canvasSize: canvasSize, layers: layers, pixelScale: pixelScale)
        inner.tracks = [track]
        inner.durationMS = lengthMS
        return inner
    }

    /// Whether everything inside is sound, which puts the merged clip on a
    /// sound track.
    var isSoundOnly: Bool { !layers.isEmpty && layers.allSatisfy(\.isSoundOnly) }

    /// Whether anything inside makes a sound.
    var speaks: Bool { layers.contains { $0.sound != nil || $0.merged?.speaks == true } }

    /// Every layer inside, however deep, merged clips inside this one
    /// included.
    var everyLayerInside: [Layer] {
        layers.flatMap { layer in layer.selfAndDescendants + (layer.merged?.everyLayerInside ?? []) }
    }

    /// The same clips with fresh ids, for a copy of the merged clip.
    func reidentified() -> MergedClip {
        var copy = self
        copy.layers = layers.map { layer in
            var fresh = layer.duplicated()
            fresh.name = layer.name
            fresh.arrivalTransition = layer.arrivalTransition
            return fresh
        }
        return copy
    }
}

// MARK: - What a layer says about it

extension Layer {

    /// Whether this layer is clips merged into one.
    public var isMergedClip: Bool { merged != nil }

    /// What this merged clip shows `innerMS` into its own clock: the clips it
    /// holds, drawn at that moment, as the children of a group standing where
    /// it does.
    func mergedContent(atInnerMS innerMS: Int, canvasSize: CGSize, pixelScale: CGFloat,
                       framesInHand: MovieFramesInHand?) -> LayerContent {
        guard let merged else { return content }
        let inner = merged.document(canvasSize: canvasSize, pixelScale: pixelScale)
        let drawn = inner.drawn(atTimeMS: innerMS, framesInHand: framesInHand)
        return .group(GroupContent(children: drawn.layers))
    }

    /// The frames this merged clip needs fetched to be drawn at a moment of the
    /// document: whatever its clips need at the moment of their own clock it
    /// lands on.
    func mergedFrameRequests(atTimeMS ms: Int, canvasSize: CGSize,
                             pixelScale: CGFloat) -> [MovieFrameRequest] {
        guard isVisible, let merged, let moment = clipMoment(atTimeMS: ms) else { return [] }
        return merged.document(canvasSize: canvasSize, pixelScale: pixelScale)
            .movieFrames(atTimeMS: moment.sourceMS)
    }

    /// What this merged clip is heard as: what its clips play, cut to the
    /// stretches of its own clock its pieces read, laid where those pieces
    /// sit. A piece played at another speed than as recorded is not heard:
    /// its sound would have to be stretched, and nothing in the mix does that
    /// to a mix yet.
    func mergedSound(canvasSize: CGSize, pixelScale: CGFloat) -> [AudioMixSegment] {
        guard let merged, let time, let pieces = clipPieces else { return [] }
        let inner = merged.document(canvasSize: canvasSize, pixelScale: pixelScale).audioMix()
        guard !inner.isEmpty else { return [] }
        var heard: [AudioMixSegment] = []
        for (index, piece) in pieces.pieces.enumerated()
        where piece.speedPercent == ClipPiece.asRecordedPercent {
            let window = piece.sourceInMS..<(piece.sourceInMS + piece.lengthMS)
            let at = time.inMS + pieces.startMS(ofPiece: index)
            for segment in inner {
                guard let cut = segment.windowed(to: window) else { continue }
                heard.append(cut.shifted(byMS: at))
            }
        }
        return heard
    }
}

extension AudioMixSegment {

    /// The same piece of sound, `delta` later on the document's clock.
    func shifted(byMS delta: Int) -> AudioMixSegment {
        AudioMixSegment(layerID: layerID, sound: sound, startMS: startMS + delta, lengthMS: lengthMS,
                        sourceInMS: sourceInMS, sourceLengthMS: sourceLengthMS,
                        speedPercent: speedPercent,
                        ramps: ramps.map {
                            AudioGainRamp(fromMS: $0.fromMS + delta, toMS: $0.toMS + delta,
                                          fromGain: $0.fromGain, toGain: $0.toGain)
                        },
                        voice: voice)
    }
}

// MARK: - Merging a range

extension PhotonzDocument {

    /// Whether any merged clip is in the document, the one question every
    /// frame asks before any of the work of drawing one.
    var hasMergedClips: Bool { layers.contains { $0.merged != nil } }

    /// Every layer merged clips hold, however deep, which is what saving a
    /// project has to keep the media of.
    public var layersInsideMergedClips: [Layer] {
        guard hasMergedClips else { return [] }
        return allLayers.flatMap { $0.merged?.everyLayerInside ?? [] }
    }

    /// The clips a merge of `range` takes in, track by track: every clip on an
    /// unlocked picture or sound track with a part inside it. Captions are
    /// words, not clips, and are left where they are.
    func clipsToMerge(within range: Range<Int>) -> [(track: DocumentTrack, clips: [UUID])] {
        guard hasTime else { return [] }
        return timelineTracks.compactMap { track in
            guard !track.isLocked, track.kind != .captions else { return nil }
            let clips = clipIDs(onTrack: track.id).filter { id in
                guard let layer = layer(id: id), let time = layer.time,
                      !layer.isCaption, !layer.isCaptionGroup else { return false }
                let lo = max(time.inMS, range.lowerBound), hi = min(time.outMS, range.upperBound)
                return hi - lo >= LayerTime.shortestMS
            }
            return clips.isEmpty ? nil : (track, clips)
        }
    }

    /// Whether Merge into One Clip has anything to merge.
    public func canMergeRange(_ range: Range<Int>) -> Bool {
        !clipsToMerge(within: range).isEmpty
    }

    /// Merge into One Clip: on every track, the parts of the clips inside
    /// `range` become one merged clip in their place, holding those clips
    /// whole. What sticks out either side stays where it was, cut at the
    /// range. Answers the merged clips made, bottom track first.
    @discardableResult
    public mutating func mergeRange(_ range: Range<Int>) -> [UUID] {
        let plan = clipsToMerge(within: range)
        guard !plan.isEmpty else { return [] }
        materializeTracks()
        var made: [UUID] = []
        for (track, ids) in plan {
            // Back to front, the order they are stacked in.
            let clips = layers.filter { ids.contains($0.id) }
            guard let origin = clips.compactMap({ $0.time?.inMS }).min(),
                  let end = clips.compactMap({ $0.time?.outMS }).max(),
                  let slot = layers.firstIndex(where: { ids.contains($0.id) }) else { continue }
            var inside: [Layer] = []
            for clip in clips {
                guard let time = clip.time else { continue }
                let before = time.inMS < range.lowerBound ? clip.clipPart(fromMS: time.inMS, toMS: range.lowerBound) : nil
                let after = range.upperBound < time.outMS ? clip.clipPart(fromMS: range.upperBound, toMS: time.outMS) : nil
                let staying = [before, after].compactMap { $0 }
                // A clip wholly inside goes in as itself; one that sticks out
                // leaves its identity with the part that stays outside.
                var held = clip
                if !staying.isEmpty {
                    held = clip.duplicated()
                    held.name = clip.name
                    held.arrivalTransition = clip.arrivalTransition
                }
                held.time = time.moved(toInMS: time.inMS - origin)
                held.trackID = track.id
                inside.append(held)
                replace(clip.id, with: staying)
            }
            let lo = max(range.lowerBound, origin), hi = min(range.upperBound, end)
            var merged = Layer(name: MergedClip.defaultName, content: .group(GroupContent()),
                               frame: CGRect(origin: .zero, size: canvasSize))
            merged.time = LayerTime(inMS: lo, outMS: hi, sourceInMS: lo - origin, sourceLengthMS: end - origin)
            merged.trackID = track.id
            merged.merged = MergedClip(layers: inside, track: track, lengthMS: end - origin)
            // The cut the range starts on, when it starts on one, is the cut
            // the merged clip arrives at, and so is its transition.
            merged.arrivalTransition = clips.first { $0.time?.inMS == lo }?.arrivalTransition
            layers.insert(merged, at: min(slot, layers.count))
            made.append(merged.id)
        }
        restackByTracks()
        return made
    }

    // MARK: - Breaking one apart

    /// Whether Break Apart can take this merged clip apart: it is one, it is
    /// not on a locked track, and every piece of it plays as recorded.
    public func canBreakApart(_ id: UUID) -> Bool {
        guard let layer = layer(id: id), layer.merged != nil, !layer.isLocked,
              !isClipOnLockedTrack(id), let pieces = layer.clipPieces else { return false }
        return pieces.pieces.allSatisfy { $0.speedPercent == ClipPiece.asRecordedPercent }
    }

    /// Break Apart: the clips a merged clip holds, back on its track where it
    /// is, showing what it was showing. A part that meets the clip it was cut
    /// from, reading on where that one stops, is joined back to it, so a
    /// merge undone this way leaves the clips as they were before it.
    /// Answers the clips that came out.
    @discardableResult
    public mutating func breakApart(_ id: UUID) -> [UUID] {
        guard canBreakApart(id), let layer = layer(id: id), let merged = layer.merged,
              let time = layer.time, let pieces = layer.clipPieces,
              let slot = layers.firstIndex(where: { $0.id == id }) else { return [] }
        materializeTracks()
        let trackID = self.layer(id: id)?.trackID ?? layer.trackID
        layers.remove(at: slot)
        var used = Set(allLayerIDs)
        var restored: [Layer] = []
        for (index, piece) in pieces.pieces.enumerated() {
            let at = time.inMS + pieces.startMS(ofPiece: index)
            let shift = at - piece.sourceInMS
            for inner in merged.layers {
                guard var part = inner.clipPart(fromMS: piece.sourceInMS,
                                                toMS: piece.sourceInMS + piece.lengthMS),
                      let partTime = part.time else { continue }
                if used.contains(part.id) {
                    let name = part.name, arrival = part.arrivalTransition
                    part = part.duplicated()
                    part.name = name
                    part.arrivalTransition = arrival
                }
                used.insert(part.id)
                part.time = partTime.moved(toInMS: partTime.inMS + shift)
                part.trackID = trackID
                // The first piece arrives at the cut the merged clip did.
                if index == 0, part.time?.inMS == time.inMS { part.arrivalTransition = layer.arrivalTransition }
                restored.append(part)
            }
        }
        layers.insert(contentsOf: restored, at: min(slot, layers.count))
        let came = restored.map(\.id)
        let out = healCuts(around: Set(came))
        restackByTracks()
        return out
    }

    /// Join each of `ids` to a clip it meets on its track when the two are
    /// one clip cut in two: the same recording reading straight on across the
    /// cut, with nothing on it. The clip already in the document keeps its
    /// identity. Answers what `ids` became.
    private mutating func healCuts(around ids: Set<UUID>) -> [UUID] {
        var result = ids
        var changed = true
        while changed {
            changed = false
            for id in result {
                guard let clip = layer(id: id), let time = clip.time, let track = clip.trackID else { continue }
                let neighbours = layers.filter { $0.id != id && $0.trackID == track }
                if let before = neighbours.first(where: { $0.time?.outMS == time.inMS }),
                   let joined = Layer.joined(before, clip, keepingSecond: result.contains(before.id)) {
                    swapJoined(joined, replacing: [before.id, id], result: &result)
                    changed = true
                    break
                }
                if let after = neighbours.first(where: { $0.time?.inMS == time.outMS }),
                   let joined = Layer.joined(clip, after, keepingSecond: !result.contains(after.id)) {
                    swapJoined(joined, replacing: [id, after.id], result: &result)
                    changed = true
                    break
                }
            }
        }
        return layers.map(\.id).filter { result.contains($0) }
    }

    private mutating func swapJoined(_ joined: Layer, replacing ids: [UUID], result: inout Set<UUID>) {
        guard let slot = layers.firstIndex(where: { ids.contains($0.id) }) else { return }
        layers.removeAll { ids.contains($0.id) }
        layers.insert(joined, at: min(slot, layers.count))
        for id in ids { result.remove(id) }
        result.insert(joined.id)
    }
}

extension Layer {

    /// `first` and `second` as the one clip they were before a cut, or nil
    /// where they are not that: they meet, they read the same media straight
    /// on across the cut at the speed it was recorded, nothing is on the cut,
    /// and nothing else about them differs. `keepingSecond` says whose
    /// identity the joined clip carries.
    static func joined(_ first: Layer, _ second: Layer, keepingSecond: Bool) -> Layer? {
        guard let a = first.time, let b = second.time, a.outMS == b.inMS,
              second.arrivalTransition == nil, first.merged == nil, second.merged == nil,
              first.name == second.name, first.frame == second.frame, first.crop == second.crop,
              first.transform == second.transform, first.style == second.style,
              first.isVisible == second.isVisible, first.isLocked == second.isLocked,
              first.motions == nil, second.motions == nil,
              first.soundLevel == second.soundLevel, first.soundDetached == second.soundDetached,
              first.trackID == second.trackID else { return nil }
        var joined = keepingSecond ? second : first
        if first.holdsMedia {
            guard first.movie == second.movie, first.sound == second.sound,
                  let ap = first.clipPieces, let bp = second.clipPieces,
                  let last = ap.pieces.last, let next = bp.pieces.first,
                  last.speedPercent == ClipPiece.asRecordedPercent,
                  next.speedPercent == ClipPiece.asRecordedPercent,
                  next.transitionIn == nil, last.sourceOutMS == next.sourceInMS else { return nil }
            let bridge = ClipPiece(sourceInMS: last.sourceInMS, lengthMS: last.lengthMS + next.lengthMS,
                                   transitionIn: last.transitionIn)
            let pieces = ClipPieces(pieces: Array(ap.pieces.dropLast()) + [bridge] + Array(bp.pieces.dropFirst()),
                                    sourceLengthMS: ap.sourceLengthMS)
            joined.time = a
            joined.cuts = nil
            joined.setClipPieces(pieces)
        } else {
            guard !second.holdsMedia, first.content == second.content else { return nil }
            joined.time = LayerTime(inMS: a.inMS, outMS: b.outMS)
        }
        joined.arrivalTransition = first.arrivalTransition
        return joined
    }
}
