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
        /// How round each of this layer's four corners is right now, whichever
        /// way it rounds.
        public let radii: CornerRadii
        /// The same as one number, for the slider: the one all four are, or the
        /// roundest of them while they disagree.
        public var radius: CGFloat { radii.uniform ?? radii.largest }
        /// Half its short edge: where its corners are already fully round.
        public let limit: CGFloat
        /// True when this layer rounds by having its corners masked off, which
        /// is a part of its look. A rectangle curves the outline it draws
        /// instead, which is part of the shape rather than part of the look.
        public let roundsViaStyle: Bool
        /// The lowest this layer's corners can be taken. Nought for everything
        /// that rounds itself; for a group, the curve its contents already
        /// have, because a group masks its corners off and a mask can never put
        /// a curve back (`ContainerRounding.swift`).
        public let floor: CornerRadii

        public init(id: UUID, radii: CornerRadii, limit: CGFloat, roundsViaStyle: Bool,
                    floor: CornerRadii = .none) {
            self.id = id
            self.radii = radii
            self.limit = limit
            self.roundsViaStyle = roundsViaStyle
            self.floor = floor
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

    /// What the four opened rows show: the corners they all wear, or that they
    /// differ.
    public var radii: StyleReading<CornerRadii> {
        guard let first = members.first?.radii else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { $0.radii != first }
        return StyleReading(value: mixed ? nil : first, isMixed: mixed)
    }

    /// What ONE opened corner row shows across everything picked.
    public func corner(_ corner: CornerRadii.Corner) -> StyleReading<Double> {
        guard let first = members.first.map({ Double($0.radii[corner]) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { Double($0.radii[corner]) != first }
        return StyleReading(value: mixed ? nil : first, isMixed: mixed)
    }

    /// Whether anything picked has a corner rounded differently from the rest
    /// of its own. What the closed row shows the four numbers for rather than
    /// a single one that would not be true.
    public var hasUnevenCorners: Bool { members.contains { !$0.radii.isUniform } }

    /// The four numbers the closed readout shows when there is one set of them
    /// to show, so a corner typed while the rows were open is still readable
    /// once they are shut.
    public var shorthand: String? { radii.value.map(\.shorthand) }

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

    /// Where the knob STARTS: the lowest anything picked can be taken.
    ///
    /// Over a group whose contents are already round this is their curve, so
    /// the knob sits where the eye says it should instead of at the far left
    /// with a dead stretch of track in front of it. It is the LOWEST floor in
    /// the selection for the same reason `limit` is the highest: a group that
    /// cannot go below 18 must not stop the plain box picked with it going all
    /// the way down.
    public var floor: Double {
        members.map { Double($0.floor.uniform ?? $0.floor.largest) }.min() ?? 0
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
    ///
    /// `skippingKnobbedCopies` leaves out a copy whose original exposes a
    /// rounding, because that copy's roundness is the knob in the Component
    /// section and its own outer mask cuts nothing anybody can see
    /// (`InstanceRounding.swift`). Asked for by the panel that has a Component
    /// section to hand the number to; the release before it asks for the row
    /// exactly as it always did.
    ///
    /// `readingWhatShows` makes the row speak for the picture rather than for
    /// the model underneath it: over a group, it reads the curve on screen and
    /// stops where the group's contents already are, instead of reading a
    /// mask nobody can see and leaving a dead stretch at the start of the pull
    /// (`ContainerRounding.swift`). Asked for by the panel that reads what is
    /// drawn; the release before it asks for the row exactly as it always did.
    public func cornerRadiusSelection(layerIDs: [UUID],
                                      cornersOnly: Bool = false,
                                      skippingKnobbedCopies: Bool = false,
                                      readingWhatShows: Bool = false,
                                      style: (Layer) -> LayerStyle = { $0.style })
    -> CornerRadiusSelection {
        var members: [CornerRadiusSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            guard !cornersOnly || layer.hasCorners else { continue }
            guard !skippingKnobbedCopies || !roundingIsAKnob(layerID: id) else { continue }
            let bounds = layer.localBounds
            let shown = readingWhatShows
                ? layer.shownCornerRadii(style: style(layer))
                : displayedCornerRadii(of: layer, style: style(layer))
            members.append(CornerRadiusSelection.Member(
                id: id,
                radii: shown,
                limit: max(1, min(bounds.width, bounds.height) / 2),
                roundsViaStyle: !layer.roundsItsOwnOutline,
                floor: readingWhatShows ? layer.cornerRadiusFloor : .none))
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
    private func displayedCornerRadii(of layer: Layer, style: LayerStyle) -> CornerRadii {
        layer.roundedCornerRadii(style: style)
    }

    /// One pull, every picked layer, each rounded the way it rounds. Returns
    /// how many took it, so a caller can tell a no-op from an edit. Locked
    /// layers are left exactly as they are.
    ///
    /// `onlyWhatShows` writes a container nothing but the part of the number
    /// that does something. A group masks its corners off and a mask can never
    /// put a curve back, so a number at or under the curve its contents already
    /// have leaves the group carrying no mask at all rather than one that cuts
    /// nothing: square the button inside it later and it goes square with it,
    /// instead of staying clipped to a curve nobody chose
    /// (`ContainerRounding.swift`).
    @discardableResult
    public mutating func setCornerRadii(layerIDs: [UUID], to radii: CornerRadii,
                                        onlyWhatShows: Bool = false) -> Int {
        let radii = radii.used
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            let floor = onlyWhatShows ? layer.cornerRadiusFloor : .none
            let wanted = floor.isRound ? radii.doingSomethingOver(floor) : radii
            // Each layer rounded the way it rounds, and the other number put to
            // nought: two radii fighting over one rectangle is the thing this
            // row exists to end (`ComponentNumberKnob.swift`, which is where a
            // number knob on a copy rounds from too, so the two can never
            // disagree).
            updateLayer(id: id) { $0.setRoundedCorners(wanted) }
            changed += 1
        }
        return changed
    }

    /// The one slider: every corner of every picked layer the same. Opening the
    /// four is the deliberate act, so the number that is always there goes on
    /// meaning what it always meant, and pulling it flattens a shape whose
    /// corners had been set apart — in ONE undo step, like any other pull.
    @discardableResult
    public mutating func setCornerRadius(layerIDs: [UUID], to radius: CGFloat) -> Int {
        setCornerRadii(layerIDs: layerIDs, to: CornerRadii(max(0, radius)))
    }

    /// ONE corner of every picked layer, leaving its other three alone. What an
    /// opened corner row writes.
    @discardableResult
    public mutating func setCornerRadius(layerIDs: [UUID], corner: CornerRadii.Corner,
                                         to radius: CGFloat,
                                         onlyWhatShows: Bool = false) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            // The same rule the one slider follows: over a container, a number
            // at or under the curve its contents already have cuts nothing, so
            // it is not written at all.
            let floor = onlyWhatShows ? layer.cornerRadiusFloor[corner] : 0
            let wanted = radius > floor ? radius : 0
            updateLayer(id: id) { $0.setRoundedCorner(corner, to: wanted) }
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
    public func boxCornerRadii(in size: CGSize) -> CornerRadii {
        guard shape == .rectangle, cornerRadii.isRound else { return .none }
        let outset = strokeOutset
        let inset = strokeWidth / 2 - outset
        let path = CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset)
        guard path.width > 0, path.height > 0 else { return .none }
        // Rounding past fully round is fully round, exactly as the rasterizer
        // clamps it, so a shape pulled thin does not grow a curve wider than it
        // is. A SQUARE corner stays square: growing it by half a line would
        // make a lozenge of a sharp box.
        return cornerRadii.fitted(in: path).grown(by: strokeWidth / 2 - outset)
    }

    /// The same, as one number, for everything that only ever wanted even
    /// corners.
    public func boxCornerRadius(in size: CGSize) -> CGFloat {
        let radii = boxCornerRadii(in: size)
        return radii.uniform ?? radii.largest
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
    public func boxCornerRadii(boxSize: CGSize) -> CornerRadii {
        let own = annotation?.boxCornerRadii(in: boxSize) ?? .none
        return own.isRound ? own : style.cornerRadii
    }

    /// The same, as one number, for everything that only ever wanted even
    /// corners.
    public func boxCornerRadius(boxSize: CGSize) -> CGFloat {
        let radii = boxCornerRadii(boxSize: boxSize)
        return radii.uniform ?? radii.largest
    }
}
