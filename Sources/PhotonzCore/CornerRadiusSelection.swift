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

    /// True when this layer has corners to round in the first place.
    ///
    /// Appearance shows a Corner Radius only where there are corners (the
    /// user's rule, 2026-09-07). An ellipse, a line and an arrow have none, and
    /// a slider that does nothing on the thing you have picked is a slider that
    /// teaches you the panel is lying. Everything that is not a shape at all —
    /// a picture, a label, a frame, a group — is a box, so it has four.
    public var hasCorners: Bool {
        guard let shape = annotation?.shape else { return true }
        switch shape {
        case .rectangle, .highlight: return true
        case .ellipse, .line, .arrow: return false
        }
    }
}

extension PhotonzDocument {

    /// What the Corner Radius row shows for a set of picked layers. Layers keep
    /// the order they are given, and locked ones are left out for the same
    /// reason every other style row leaves them out.
    ///
    /// `style` is how a caller reads one layer's look, so the panel can hand in
    /// the style a drag is previewing and have the row read what is on screen
    /// rather than what is on disk.
    ///
    /// `cornersOnly` leaves out the picked layers that have no corners, for the
    /// Appearance panel's rule that the row is there only where there are
    /// corners to round. The count of everything picked is kept either way, so
    /// the row can still say how many layers it is speaking for.
    public func cornerRadiusSelection(layerIDs: [UUID],
                                      cornersOnly: Bool = false,
                                      style: (Layer) -> LayerStyle = { $0.style })
    -> CornerRadiusSelection {
        var members: [CornerRadiusSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            guard !cornersOnly || layer.hasCorners else { continue }
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
        layer.roundedCornerRadius(style: style)
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
            // Each layer rounded the way it rounds, and the other number put to
            // nought: two radii fighting over one rectangle is the thing this
            // row exists to end (`ComponentNumberKnob.swift`, which is where a
            // number knob on a copy rounds from too, so the two can never
            // disagree).
            updateLayer(id: id) { $0.setRoundedCorners(radius) }
            changed += 1
        }
        return changed
    }
}

// MARK: - The curve everything round a layer's box follows

extension AnnotationContent {

    /// How round the shape's SILHOUETTE is where it meets the shape's own
    /// frame: the line a ring round the box, or a mask cut out of it, has to
    /// follow. Zero for anything that is not a rectangle, and for a rectangle
    /// that is not rounded.
    ///
    /// `cornerRadius` is the radius of the path the stroke rides, and that
    /// path is not the frame: it is inset by half a width for an inside
    /// outline, sits on the frame for a centred one, and is pushed half a width
    /// out for an outside one (`AnnotationRasterizer`). The silhouette is that
    /// path grown by half a width, so the curve at the frame is half a width
    /// wider than the path's, less however far the whole thing was pushed past
    /// the frame.
    ///
    /// `size` is the shape's box in the same unit its numbers are stated in,
    /// which is document points.
    public func boxCornerRadius(in size: CGSize) -> CGFloat {
        guard shape == .rectangle, cornerRadius > 0 else { return 0 }
        let outset = strokeOutset
        let inset = strokeWidth / 2 - outset
        let path = CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset)
        guard path.width > 0, path.height > 0 else { return 0 }
        // Rounding past fully round is fully round, exactly as the rasterizer
        // clamps it, so a shape pulled thin does not grow a curve wider than it
        // is.
        let radius = min(cornerRadius, min(path.width, path.height) / 2)
        return max(0, radius + strokeWidth / 2 - outset)
    }
}

extension Layer {

    /// How round this layer's own box is: the one curve every ring round it,
    /// and every mask cut out of it, follows.
    ///
    /// A rectangle curves the outline it draws, so its own curve answers here
    /// — the layer style's radius is deliberately nought on one, which is why
    /// a border added to a rounded box used to come out a hard square frame
    /// (reported by the user, 2026-09-07). Everything else is rounded by the
    /// mask its look carries, and so is a rectangle rounded by nothing but that
    /// old mask, so a document written before the one Corner Radius row paints
    /// what it always painted (`roundedCornerRadius`).
    ///
    /// `boxSize` is the layer's box in the unit the shape's own numbers are
    /// stated in, which is document points.
    public func boxCornerRadius(boxSize: CGSize) -> CGFloat {
        let own = annotation?.boxCornerRadius(in: boxSize) ?? 0
        return own > 0 ? own : style.cornerRadius
    }
}
