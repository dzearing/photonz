import CoreGraphics
import Foundation

// **The timeline is the layers list with a time axis** (the user, 2026-10-17:
// "the timeline is similar to the layers pane, but it allows you to adjust
// horizontally on a timeline when it appears and how it transitions"). Task
// `any-timeline-row-that-holds-sub-layers-expands-a`.
//
// Anything made of parts (a title page, a name card, a group, a logo with
// layers, a component) has an arrow on its row, and opened, each part is a row
// of its own one step in, with its own bar. The rows, their nesting and their
// order are the layers list's, and they open from the same set of open groups,
// so opening a group in one opens it in the other.

/// One row under a clip on the timeline: a part, how deep it is, and whether
/// it has an arrow of its own.
public struct TimelineChildRow: Hashable, Sendable {
    public var layerID: UUID
    /// The row it hangs from: the clip, or a part further out.
    public var parentID: UUID
    /// One for a part of the clip itself, two for a part of one of those.
    public var depth: Int
    /// It has parts of its own, so it wears an arrow.
    public var opens: Bool
    public var isOpen: Bool
}

extension PhotonzDocument {

    /// The parts a row lists, top first. A title's are its parts as the
    /// Title section names them; anything else's are its children, in the
    /// layers list's order. Captions list nothing: their cues are their own
    /// track.
    public func timelineChildIDs(of id: UUID) -> [UUID] {
        guard let layer = layer(id: id), layer.isGroup, !layer.isCaptionsLayer else { return [] }
        if Self.isPlacedTitle(layer) {
            let pieces = Set(titlePartTimings(layerID: id).map(\.pieceID))
            // In the order the layers list draws them: top first.
            return layer.selfAndDescendants.dropFirst().reversed().map(\.id).filter(pieces.contains)
        }
        return layer.children.reversed().map(\.id)
    }

    /// Whether a row has parts to open into, which is what earns it an arrow.
    public func timelineRowOpens(_ id: UUID) -> Bool { !timelineChildIDs(of: id).isEmpty }

    /// The rows under clip `clipID`: every part of an open row, one step in per
    /// level, and, under a closed one, only the part picked and the groups it
    /// is in, so a pick never pushes the tracks under it out of sight.
    public func timelineChildRows(of clipID: UUID, open: Set<UUID>, picked: UUID?) -> [TimelineChildRow] {
        // The part picked and every group it is in.
        var chain = Set<UUID>()
        if let picked, picked != clipID {
            chain.insert(picked)
            var here = parentID(of: picked)
            while let id = here, id != clipID {
                chain.insert(id)
                here = parentID(of: id)
            }
        }
        var rows: [TimelineChildRow] = []
        func walk(_ id: UUID, depth: Int) {
            let isOpen = open.contains(id)
            for child in timelineChildIDs(of: id) where isOpen || chain.contains(child) {
                let childOpen = open.contains(child)
                rows.append(TimelineChildRow(layerID: child, parentID: id, depth: depth,
                                             opens: timelineRowOpens(child), isOpen: childOpen))
                walk(child, depth: depth + 1)
            }
        }
        walk(clipID, depth: 1)
        return rows
    }

    /// Option-click on an arrow: the row and every part inside it that has
    /// parts of its own, at every level, the way the layers list's does.
    public func timelineRowsOpeningEveryLevel(from id: UUID) -> Set<UUID> {
        guard timelineRowOpens(id) else { return [] }
        var out: Set<UUID> = [id]
        for child in timelineChildIDs(of: id) { out.formUnion(timelineRowsOpeningEveryLevel(from: child)) }
        return out
    }

    /// Where a closed row's parts are on screen when that is not the whole of
    /// the row: the faint marks along its bar that say there is timing inside
    /// to open up and change. A part that runs the whole way is not marked.
    public func timelineChildMarks(of id: UUID) -> [LayerTime] {
        guard let layer = layer(id: id), let whole = layer.time else { return [] }
        if Self.isPlacedTitle(layer) {
            return titlePartTimings(layerID: id).compactMap { part in
                let start = part.titleInMS + part.startMS, end = part.titleInMS + part.endMS
                return start == whole.inMS && end == whole.outMS ? nil : LayerTime(inMS: start, outMS: end)
            }
        }
        return timelineChildIDs(of: id).compactMap { child in
            let stretch = partStretch(of: child).map { ($0.startMS, $0.endMS) }
                ?? self.layer(id: child)?.time.map { ($0.inMS, $0.outMS) }
            guard let (start, end) = stretch, start != whole.inMS || end != whole.outMS else { return nil }
            return LayerTime(inMS: start, outMS: end)
        }
    }

    /// A title page or name card placed on the timeline, whose parts are read
    /// off its design rather than its children.
    static func isPlacedTitle(_ layer: Layer) -> Bool {
        layer.group?.titleRecipe != nil && layer.isPlacedInTime && !layer.isComponentInstance
    }
}
