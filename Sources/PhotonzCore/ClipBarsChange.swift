import Foundation

/// Which clips' bars on the timeline an edit changed: what lets a bar be
/// built again only when something it draws has changed, instead of for
/// every edit to any clip (`docs/design/video.md` §8f, rule 7).
///
/// A bar draws its own clip (its pieces, cuts, keys, fades, level, name), and
/// three things that come from elsewhere in the document: whether it meets
/// the clips either side of it on its track (an edit point), the drift marks
/// a hold that pushed the picture alone puts on it, and its track (locked,
/// which kind). So an edit that only changed some clips' own values changes
/// those bars and the ones on the same track that touched them before or
/// touch them now, and a clip added or taken away (a paste, a delete, the undo of
/// one) changes its own and the ones it meets, on a track that came or went
/// with it or not. Any other change (clips reordered, a track that stays
/// changed, a hold that pushes the picture alone, anything else outside the
/// layers) changes every bar.
public enum ClipBarsChange: Equatable, Sendable {
    /// Every bar may draw differently.
    case every
    /// Only these clips' bars (and anything inside them) may.
    case only(Set<UUID>)

    public static let none = ClipBarsChange.only([])

    public func contains(_ id: UUID) -> Bool {
        switch self {
        case .every: true
        case .only(let ids): ids.contains(id)
        }
    }
}

extension PhotonzDocument {

    /// What changed for the timeline's clip bars between `old` and this one.
    public func clipBarsChange(since old: PhotonzDocument) -> ClipBarsChange {
        // By place, not by copy: a layer is big, and a long edit has hundreds.
        let same = old.layers.count == layers.count && layers.indices.allSatisfy { old.layers[$0].id == layers[$0].id }
        let was = same ? [:] : Self.places(old.layers)
        let now = same ? [:] : Self.places(layers)
        // The layers in both, in the one order.
        guard same || old.layers.indices.map({ old.layers[$0].id }).filter({ now[$0] != nil })
            == layers.indices.map({ layers[$0].id }).filter({ was[$0] != nil }) else { return .every }
        var outside = old
        outside.layers = []
        var mine = self
        mine.layers = []
        // A track that came or went is drawn on no other track's bar.
        if outside.tracks != mine.tracks {
            let before = Set(outside.tracks.map(\.id)), after = Set(mine.tracks.map(\.id))
            outside.tracks.removeAll { !after.contains($0.id) }
            mine.tracks.removeAll { !before.contains($0.id) }
        }
        guard outside == mine else { return .every }
        var changed: [(old: Layer?, new: Layer?)] = []
        for index in old.layers.indices {
            guard let still = same ? index : now[old.layers[index].id] else {
                changed.append((old.layers[index], nil))
                continue
            }
            if !layers.layer(at: still, isTheSameAs: index, in: old.layers) {
                changed.append((old.layers[index], layers[still]))
            }
        }
        if !same {
            for index in layers.indices where was[layers[index].id] == nil { changed.append((nil, layers[index])) }
        }
        let oldLayout = old.trackLayout(), newLayout = trackLayout()
        if changed.isEmpty, oldLayout.tracks == newLayout.tracks { return .none }
        guard Self.sameWhereBothStand(oldLayout, newLayout, goneOrCome: Set(changed.compactMap { pair in
            pair.old == nil || pair.new == nil ? (pair.old ?? pair.new)?.id : nil
        })) else { return .every }
        guard Self.sameHolds(old.pictureOnlyHolds, pictureOnlyHolds) else { return .every }
        var ids = Set<UUID>()
        for pair in changed {
            for layer in [pair.old, pair.new].compactMap({ $0 }) {
                for inside in layer.selfAndDescendants { ids.insert(inside.id) }
            }
            // The clips on its track it touched before or touches now: an
            // edit point there may have come or gone.
            guard let layer = pair.new ?? pair.old else { continue }
            let span = [pair.old?.time, pair.new?.time].compactMap { $0 }
            guard let start = span.map(\.inMS).min(), let end = span.map(\.outMS).max(),
                  let track = pair.new != nil ? trackID(ofClip: layer.id) : old.trackID(ofClip: layer.id)
            else { continue }
            for other in Set(clipIDs(onTrack: track) + old.clipIDs(onTrack: track)) where other != layer.id {
                for document in [old, self] {
                    guard let time = document.layer(id: other)?.time,
                          time.inMS <= end, time.outMS >= start else { continue }
                    ids.insert(other)
                }
            }
        }
        return .only(ids)
    }

    private static func places(_ layers: [Layer]) -> [UUID: Int] {
        Dictionary(layers.indices.map { (layers[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The tracks whose rows draw something `change` (this document's change
    /// since `old`) reached: the ones that hold a changed clip now or held it
    /// before. Nil for every row, where every bar may draw differently or the
    /// document came to have a clock or lost it. A row draws nothing else of
    /// another track's: its gaps, cuts, marks and key lanes are all read off
    /// its own clips, and its place and the ruler reach it another way.
    public func tracksDrawn(differentlyBy change: ClipBarsChange, since old: PhotonzDocument) -> Set<UUID>? {
        guard case .only(let ids) = change, hasKeyClock == old.hasKeyClock else { return nil }
        guard !ids.isEmpty else { return [] }
        var tracks = Set<UUID>()
        for layout in [old.trackLayout(), trackLayout()] {
            for members in [layout.clips, layout.linked] {
                for (track, clips) in members where clips.contains(where: ids.contains) { tracks.insert(track) }
            }
        }
        return tracks
    }

    /// Whether the tracks in both hold the same clips in the same order, apart
    /// from the clips that came or went, and a clip in both is on the same one.
    private static func sameWhereBothStand(_ a: TrackLayout, _ b: TrackLayout, goneOrCome: Set<UUID>) -> Bool {
        if a.tracks == b.tracks, a.clips == b.clips, a.linked == b.linked { return true }
        let before = Set(a.tracks.map(\.id)), after = Set(b.tracks.map(\.id))
        guard a.tracks.filter({ after.contains($0.id) }) == b.tracks.filter({ before.contains($0.id) }) else { return false }
        func kept(_ clips: [UUID: [UUID]]) -> [UUID: [UUID]] {
            clips.mapValues { $0.filter { !goneOrCome.contains($0) } }.filter { !$0.value.isEmpty }
        }
        return kept(a.clips) == kept(b.clips) && kept(a.linked) == kept(b.linked)
    }

    private static func sameHolds(_ a: [DocumentDerived.PictureOnlyHold],
                                  _ b: [DocumentDerived.PictureOnlyHold]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.layerID == $1.layerID && $0.atMS == $1.atMS && $0.lengthMS == $1.lengthMS
        }
    }
}
