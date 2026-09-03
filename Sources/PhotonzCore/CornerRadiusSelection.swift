import CoreGraphics
import Foundation

/// What the ONE Corner Radius row reads and writes, over everything picked.
///
/// Rounding means two different things underneath. A rectangle rounds by
/// curving the outline it draws, so the curve follows its border; a picture, a
/// frame or a group rounds by having its corners masked off. The panel used to
/// carry a slider for each of those, one in the shape's own section and one
/// under Effects, both labelled Corner Radius, with nothing to say which was
/// which or what happened when they disagreed (they fought: the mask chopped
/// the corners off the rectangle's outline).
///
/// So there is one row. It reads whichever number is actually rounding each
/// picked layer and writes back to whichever field rounds it properly, which
/// means one slider can round a screenshot and a box drawn on top of it in the
/// same pull.
public struct CornerRadiusSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        /// How round this layer is right now, whichever way it rounds.
        public let radius: CGFloat
        /// Half its short edge: where its corners are already fully round.
        public let limit: CGFloat
        /// True when this layer rounds by having its corners masked off, which
        /// is a part of its look. A rectangle curves the outline it draws
        /// instead, which is part of the shape rather than part of the look.
        public let roundsViaStyle: Bool

        public init(id: UUID, radius: CGFloat, limit: CGFloat, roundsViaStyle: Bool) {
            self.id = id
            self.radius = radius
            self.limit = limit
            self.roundsViaStyle = roundsViaStyle
        }
    }

    public let members: [Member]
    /// How many layers are picked altogether, including the ones this row
    /// skips, so it can say what it does and does not reach.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }

    /// The layers a drag in this row rounds, in the order they were given.
    public var layerIDs: [UUID] { members.map(\.id) }

    /// What the row shows: the number they all wear, or that they differ.
    public var reading: StyleReading<Double> {
        guard let first = members.first.map({ Double($0.radius) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { Double($0.radius) != first }
        return StyleReading(value: first, isMixed: mixed)
    }

    /// Where the knob stops: the largest picked layer's fully round. A small
    /// box in the selection must not stop a big one going round, and rounding
    /// past a layer's own half-edge simply does nothing to it.
    public var limit: Double {
        max(1, members.map { Double($0.limit) }.max() ?? 1)
    }

    /// The one picked layer whose rounding is a part of its look that a copy
    /// of a component can own, when exactly one is picked and it rounds that
    /// way. It is what puts the "follow the original again" arrow on this row,
    /// and a rectangle never gets one because its curve is not part of its
    /// look.
    public var soleStyleRoundedID: UUID? {
        guard members.count == 1, let only = members.first, only.roundsViaStyle else { return nil }
        return only.id
    }

    /// What the row says out loud when it is leaving a picked layer out.
    public var note: String? {
        guard count > 0, count < selectionCount else { return nil }
        return "Applies to \(count) of the \(selectionCount) selected layers."
    }
}

extension Layer {

    /// True when rounding this layer curves the outline it draws rather than
    /// masking the picture of it. Only a rectangle has an outline with corners
    /// on it to curve.
    var roundsItsOwnOutline: Bool { annotation?.shape == .rectangle }
}

extension PhotonzDocument {

    /// What the Corner Radius row shows for a set of picked layers. Layers keep
    /// the order they are given, and locked ones are left out for the same
    /// reason every other style row leaves them out.
    ///
    /// `style` is how a caller reads one layer's look, so the panel can hand in
    /// the style a drag is previewing and have the row read what is on screen
    /// rather than what is on disk.
    public func cornerRadiusSelection(layerIDs: [UUID],
                                      style: (Layer) -> LayerStyle = { $0.style })
    -> CornerRadiusSelection {
        var members: [CornerRadiusSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            let bounds = layer.localBounds
            members.append(CornerRadiusSelection.Member(
                id: id,
                radius: displayedCornerRadius(of: layer, style: style(layer)),
                limit: max(1, min(bounds.width, bounds.height) / 2),
                roundsViaStyle: !layer.roundsItsOwnOutline))
        }
        return CornerRadiusSelection(members: members, selectionCount: layerIDs.count)
    }

    /// The number the row shows for one layer: the one that is rounding it.
    ///
    /// A rectangle's own curve normally speaks for it. The exception is a
    /// rectangle rounded by the old mask and nothing else, which is what the
    /// second slider left behind: reading zero there would be a row denying
    /// what is plainly on the canvas, so it reads the mask, and the first nudge
    /// moves that rounding onto the outline where it belongs.
    private func displayedCornerRadius(of layer: Layer, style: LayerStyle) -> CGFloat {
        guard layer.roundsItsOwnOutline else { return style.cornerRadius }
        let own = layer.annotation?.cornerRadius ?? 0
        return own > 0 ? own : style.cornerRadius
    }

    /// One pull, every picked layer, each rounded the way it rounds. Returns
    /// how many took it, so a caller can tell a no-op from an edit. Locked
    /// layers are left exactly as they are.
    @discardableResult
    public mutating func setCornerRadius(layerIDs: [UUID], to radius: CGFloat) -> Int {
        let radius = max(0, radius)
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            if layer.roundsItsOwnOutline, var annotation = layer.annotation {
                annotation.cornerRadius = radius
                updateLayer(id: id) {
                    $0.content = .annotation(annotation)
                    // The old mask goes with it. Two radii fighting over one
                    // rectangle is the thing this row exists to end, and the
                    // mask is the one that chops the outline.
                    $0.style.cornerRadius = 0
                }
            } else {
                updateLayer(id: id) { $0.style.cornerRadius = radius }
            }
            changed += 1
        }
        return changed
    }
}
