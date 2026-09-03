import CoreGraphics
import Foundation

/// What one Effects or Shadow row reads when it is speaking for more than one
/// layer.
///
/// Four buttons that are all 8pt round have one thing to say. Four that differ
/// have none, and printing one of their numbers would be a row claiming a value
/// three of the layers under it are not wearing — which is also how you round
/// three corners you never meant to touch, the moment you nudge the slider. So
/// the row either says what they agree on or says out loud that they differ.
public struct StyleReading<Value: Hashable & Sendable>: Hashable, Sendable {
    /// Where the control sits. What they all say when they agree; the first
    /// picked layer's when they do not, because a knob has to be somewhere and
    /// the same selection should read the same way twice running. The READOUT
    /// beside it says Mixed, so the position is a starting point rather than a
    /// claim. Nil when the row speaks for nothing at all.
    public let value: Value?
    public let isMixed: Bool

    public init(value: Value?, isMixed: Bool) {
        self.value = value
        self.isMixed = isMixed
    }

    public var isEmpty: Bool { value == nil }
}

extension StyleReading where Value == Bool {
    /// True only when every layer the row speaks for says yes. Three boxes
    /// where one is shadowed read off, so one click shadows the other two
    /// rather than un-shadowing the first — the same rule the Fill checkbox
    /// follows over a half-filled selection.
    public var isEverywhere: Bool { value == true && !isMixed }
}

/// The layers one Effects or Shadow row speaks for, and what a drag in it does
/// to all of them.
///
/// One layer or twenty, the row means the same thing: this is Corner Radius,
/// and dragging it rounds everything picked. That is what turns "round these
/// four buttons" into one move instead of four, and one undo instead of four.
///
/// A layer sits out when the row cannot honestly reach it: a locked layer must
/// not be restyled by a drag aimed at the layers on top of it. The row says how
/// many of the picked layers it is speaking for whenever that is not all of
/// them.
public struct LayerStyleSelection: Hashable, Sendable {

    /// One picked layer's look, and the one thing about its shape a style row
    /// has to know.
    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let style: LayerStyle
        /// Half this layer's short edge. Rounding past it does nothing you can
        /// see, so it is where this layer's corners are already fully round.
        public let cornerRadiusLimit: Double
        /// True when a line round this layer is part of what it IS: a shape
        /// strokes its own outline, so its width belongs on the shape's own
        /// Thickness row and the Border row leaves it alone. See
        /// `OutlineWidth.swift`.
        public let drawsItsOwnOutline: Bool

        public init(id: UUID, style: LayerStyle, cornerRadiusLimit: Double,
                    drawsItsOwnOutline: Bool = false) {
            self.id = id
            self.style = style
            self.cornerRadiusLimit = cornerRadiusLimit
            self.drawsItsOwnOutline = drawsItsOwnOutline
        }
    }

    /// What a row shows in place of a number when the layers differ.
    public static let mixedText = "Mixed"

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

    /// The layers a drag in this row restyles, in the order they were given.
    public var layerIDs: [UUID] { members.map(\.id) }

    /// What one row reads: the thing they all say, or that they differ.
    public func reading<Value: Hashable & Sendable>(
        _ read: (LayerStyle) -> Value
    ) -> StyleReading<Value> {
        guard let first = members.first.map({ read($0.style) }) else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { read($0.style) != first }
        return StyleReading(value: first, isMixed: mixed)
    }

    /// The same reading for the rows that carry a slider.
    public func number(_ read: (LayerStyle) -> CGFloat) -> StyleReading<Double> {
        reading { Double(read($0)) }
    }

    /// Where the Corner Radius slider stops: the largest picked layer's fully
    /// round. A small box in the selection must not stop a big one going round,
    /// and rounding past a layer's own half-edge simply does nothing to it.
    public var cornerRadiusLimit: Double {
        max(1, members.map(\.cornerRadiusLimit).max() ?? 1)
    }

    /// Whether every layer the row speaks for draws a shadow, which is what the
    /// Shadow switch reads.
    public var hasShadowEverywhere: Bool {
        !members.isEmpty && members.allSatisfy { $0.style.shadow != nil }
    }

    /// The picked layers that have a shadow to talk about. The shadow's own
    /// rows speak for these, so Softness over a selection where one box is
    /// unshadowed changes the two that are rather than inventing a shadow on
    /// the third.
    public var shadows: LayerStyleSelection {
        LayerStyleSelection(members: members.filter { $0.style.shadow != nil },
                            selectionCount: selectionCount)
    }

    /// What the row says out loud when it is leaving a picked layer out: a
    /// locked one, or (for the shadow rows) one with no shadow yet. Nil when it
    /// reaches everything, because a sentence saying "this does what it looks
    /// like it does" is a sentence in the way.
    public var note: String? {
        guard count > 0, count < selectionCount else { return nil }
        return "Applies to \(count) of the \(selectionCount) selected layers."
    }
}

extension ShadowStyle {

    /// How far the shadow is thrown from the object, in points.
    public var distance: CGFloat { hypot(offset.width, offset.height) }

    /// Which way it is thrown, in degrees, one whole turn's worth. A shadow
    /// sitting exactly under its object has no direction of its own, so it
    /// reads as straight down and the Direction control still means something.
    public var directionDegrees: CGFloat {
        guard offset.width != 0 || offset.height != 0 else { return 90 }
        let degrees = atan2(offset.height, offset.width) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Throws the shadow further or nearer, the way it is already pointing.
    public mutating func setDistance(_ distance: CGFloat) {
        let radians = directionDegrees * .pi / 180
        offset = CGSize(width: distance * cos(radians), height: distance * sin(radians))
    }

    /// Turns the shadow, keeping how far it is thrown. A shadow with nowhere
    /// to be thrown steps one point out, so turning the dial does something you
    /// can see rather than nothing at all.
    public mutating func setDirectionDegrees(_ degrees: CGFloat) {
        let radians = degrees * .pi / 180
        let thrown = max(distance, 1)
        offset = CGSize(width: thrown * cos(radians), height: thrown * sin(radians))
    }
}

extension PhotonzDocument {

    /// What the Effects and Shadow rows show for a set of picked layers. Layers
    /// keep the order they are given, which is the order the panel lists them
    /// in, and locked ones are left out for the same reason the color rows
    /// leave them out.
    ///
    /// `style` is how a caller reads one layer's look: the panel hands in the
    /// style a slider drag is previewing, so the rows read what is on screen
    /// rather than what is on disk.
    public func layerStyleSelection(layerIDs: [UUID],
                                    style: (Layer) -> LayerStyle = { $0.style })
    -> LayerStyleSelection {
        var members: [LayerStyleSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            var resolved = style(layer)
            // A label whose halo the surface draws for it has no shadow of its
            // own to talk about: a switch reading "on" there would be describing
            // a shadow nobody can see.
            if isOnDesignedSurface(id) {
                var probe = layer
                probe.style = resolved
                resolved.shadow = probe.drawnShadow(onDesignedSurface: true)
            }
            let bounds = layer.localBounds
            members.append(LayerStyleSelection.Member(
                id: id, style: resolved,
                cornerRadiusLimit: max(1, Double(min(bounds.width, bounds.height) / 2)),
                drawsItsOwnOutline: layer.drawsItsOwnOutline))
        }
        return LayerStyleSelection(members: members, selectionCount: layerIDs.count)
    }

    /// One drag, every picked layer. Returns how many took it, so a caller can
    /// tell a no-op from an edit. Locked layers are left exactly as they are.
    @discardableResult
    public mutating func updateLayerStyles(layerIDs: [UUID],
                                           _ mutate: (inout LayerStyle) -> Void) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            updateLayer(id: id) { mutate(&$0.style) }
            changed += 1
        }
        return changed
    }
}
