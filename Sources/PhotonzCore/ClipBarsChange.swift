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
/// touch them now; any other change (a clip added, taken away or reordered,
/// a track, a hold that pushes the picture alone, anything outside the
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
        guard old.layers.count == layers.count,
              zip(old.layers, layers).allSatisfy({ $0.id == $1.id }) else { return .every }
        var outside = old
        outside.layers = []
        var mine = self
        mine.layers = []
        guard outside == mine else { return .every }
        var changed: [(old: Layer, new: Layer)] = []
        for (was, now) in zip(old.layers, layers) where was != now { changed.append((was, now)) }
        if changed.isEmpty { return .none }
        let oldLayout = old.trackLayout(), newLayout = trackLayout()
        guard oldLayout.tracks == newLayout.tracks, oldLayout.clips == newLayout.clips,
              oldLayout.linked == newLayout.linked else { return .every }
        guard Self.sameHolds(old.pictureOnlyHolds, pictureOnlyHolds) else { return .every }
        var ids = Set<UUID>()
        for pair in changed {
            for layer in [pair.old, pair.new] {
                for inside in layer.selfAndDescendants { ids.insert(inside.id) }
            }
            // The clips on its track it touched before or touches now: an
            // edit point there may have come or gone.
            let span = [pair.old.time, pair.new.time].compactMap { $0 }
            guard let start = span.map(\.inMS).min(), let end = span.map(\.outMS).max(),
                  let track = trackID(ofClip: pair.new.id) else { continue }
            for other in clipIDs(onTrack: track) where other != pair.new.id {
                for document in [old, self] {
                    guard let time = document.layer(id: other)?.time,
                          time.inMS <= end, time.outMS >= start else { continue }
                    ids.insert(other)
                }
            }
        }
        return .only(ids)
    }

    private static func sameHolds(_ a: [DocumentDerived.PictureOnlyHold],
                                  _ b: [DocumentDerived.PictureOnlyHold]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.layerID == $1.layerID && $0.atMS == $1.atMS && $0.lengthMS == $1.lengthMS
        }
    }
}
