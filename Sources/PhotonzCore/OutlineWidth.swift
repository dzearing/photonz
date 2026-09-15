import CoreGraphics
import Foundation

/// ONE width for the line round a layer, and ONE place it lives.
///
/// A rectangle used to offer two: Thickness in the shape's own section and
/// Border under Effects. They are the same ring — a shape's stroke and a ring
/// hugging the same box land on identical pixels at the same width — so with
/// both set the border simply covered the stroke and the second slider silently
/// won, in a different colour.
///
/// That is settled now: a box and an oval have no stroke of their own at all.
/// Their edge is a Border in the Effects list, like the ring round a picture,
/// like every other line round every other layer (`OutlineRetirement.swift`).
/// A line and an arrow are the exception, because their stroke IS the layer:
/// taking it off would be a delete, so its width stays in the shape's own
/// settings beside the ending and the head size.
extension Layer {

    /// True when the stroke IS the layer rather than a line round it: a line
    /// and an arrow, and nothing else.
    ///
    /// A box and an oval used to be here too, back when they strokes their own
    /// path. Their edge is a Border in the Effects list now, exactly like the
    /// ring round a picture, so there is one kind of edge in the app and this
    /// answers for the two shapes that do not have one at all
    /// (`OutlineRetirement.swift`).
    public var drawsItsOwnOutline: Bool {
        // A path strokes its own outline and cannot do anything else: a ring
        // round its BOX would be a rectangle round a shape that is not one, so
        // its edge stays where the shape is (`docs/design/vector-paths.md`).
        if path != nil { return true }
        guard let annotation else { return false }
        return !annotation.drawsARingRatherThanBeingOne && annotation.shape != .highlight
    }

    /// The width of the one line round this layer, wherever that line lives:
    /// the stroke a line or an arrow IS, or the ring nearest the eye in the
    /// Effects list.
    public var outlineWidth: CGFloat {
        if let path { return max(path.strokeWidth, style.borderWidth) }
        guard let annotation, drawsItsOwnOutline else { return style.borderWidth }
        return max(annotation.strokeWidth, style.borderWidth)
    }

    /// What that line is drawn in, gradient and all.
    public var outlinePaint: Paint {
        if let path { return path.paint }
        guard let annotation, drawsItsOwnOutline else {
            return style.borderEffects.first?.paint ?? Paint(hex: style.borderColorHex)
        }
        return annotation.paint
    }

    /// The one flat colour it stands for.
    var outlineColorHex: String { outlinePaint.hex }
}

extension ShapeSelection.Member {

    /// What the Thickness row reads for this one shape: the ring on screen.
    public var outlineWidth: CGFloat { max(content.strokeWidth, styleBorderWidth) }
}

extension ShapeSelection {

    /// What the Thickness row shows: the width they all wear, or that they
    /// differ.
    public var outlineWidth: StyleReading<CGFloat> {
        guard let first = members.first?.outlineWidth else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { $0.outlineWidth != first }
        return StyleReading(value: first, isMixed: mixed)
    }
}

extension LayerStyleSelection {

    /// The picked layers the old Border row can honestly reach: the ones with
    /// no Thickness of their own. A rectangle picked alongside a screenshot
    /// takes the border off its own row and leaves the screenshot's alone.
    public var borders: LayerStyleSelection {
        LayerStyleSelection(members: members.filter { !$0.hasItsOwnThickness },
                            selectionCount: selectionCount)
    }
}

extension PhotonzDocument {

    /// One pull on Thickness, every picked shape. Returns how many took it, so
    /// a caller can tell a no-op from an edit. Locked layers, and layers with
    /// no outline of their own, are left exactly as they are.
    ///
    /// A ring the old Border slider left behind is folded onto the stroke here,
    /// color and all, so the shape keeps the look it had and ends up with one
    /// ring instead of two.
    @discardableResult
    public mutating func setOutlineWidth(layerIDs: [UUID], to width: CGFloat) -> Int {
        let width = max(0, width)
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, layer.hasOutlineThickness
            else { continue }
            // The border goes with it. Two rings round one box, one of them
            // hidden under the other, is the thing this row exists to end, and
            // a number knob on a copy sets its thickness through the same one
            // step (`ComponentNumberKnob.swift`).
            updateLayer(id: id) { $0.setOutlineWidth(width) }
            changed += 1
        }
        return changed
    }
}

extension Layer {

    /// Whether a Thickness has anything to set on this layer.
    ///
    /// Every shape but a highlight: a line and an arrow have a stroke, a box
    /// and an oval have an edge in their Effects list, and a highlight is a
    /// wash with neither. A path the Pen drew is here too — its stroke IS the
    /// drawing, so the weight it came out at is a weight somebody has to be
    /// able to change afterwards.
    public var hasOutlineThickness: Bool {
        if path != nil { return true }
        guard let annotation else { return false }
        return annotation.shape != .highlight
    }
}

// MARK: - What the Thickness row speaks for

/// The picked layers the ONE Thickness row reaches, and the weight it shows
/// across them.
///
/// It is its own reading rather than a question asked of `ShapeSelection`
/// because that selection is a list of `AnnotationContent`s: it is what the
/// Ending picker, the head size and the caption rows all read, and a path has
/// none of those. What a path DOES have is a line of its own, which is the one
/// thing this row asks about, so this widens exactly that question and nothing
/// else.
public struct OutlineThicknessSelection: Hashable, Sendable {

    public struct Member: Hashable, Sendable {
        public let id: UUID
        /// The ring actually on screen: a shape's stroke, a path's, or a ring
        /// the old Effects Border slider left behind.
        public let width: CGFloat

        public init(id: UUID, width: CGFloat) {
            self.id = id
            self.width = width
        }
    }

    public let members: [Member]
    /// How many layers are picked altogether, so the row can say what it is
    /// leaving out.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }
    public var layerIDs: [UUID] { members.map(\.id) }

    /// The part of this selection one row speaks for. Pick a path and a box
    /// together and the stroke row reaches the path alone, so its Thickness
    /// has to reach the path alone too.
    public func of(_ ids: [UUID]) -> OutlineThicknessSelection {
        let wanted = Set(ids)
        return OutlineThicknessSelection(members: members.filter { wanted.contains($0.id) },
                                         selectionCount: ids.count)
    }

    /// What the row shows: the weight they all wear, or that they differ.
    public var reading: StyleReading<CGFloat> {
        guard let first = members.first?.width else {
            return StyleReading(value: nil, isMixed: false)
        }
        let mixed = members.dropFirst().contains { $0.width != first }
        return StyleReading(value: first, isMixed: mixed)
    }
}

extension PhotonzDocument {

    /// The Thickness row's view of a set of picked layers, in the order given:
    /// every unlocked one with a line of its own, shapes and drawn paths alike.
    public func outlineThicknessSelection(layerIDs: [UUID]) -> OutlineThicknessSelection {
        var members: [OutlineThicknessSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, layer.hasOutlineThickness
            else { continue }
            members.append(OutlineThicknessSelection.Member(id: id, width: layer.outlineWidth))
        }
        return OutlineThicknessSelection(members: members, selectionCount: layerIDs.count)
    }
}
