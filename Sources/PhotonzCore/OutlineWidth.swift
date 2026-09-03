import CoreGraphics
import Foundation

/// ONE width for the line round a layer.
///
/// A rectangle used to offer two of them: Thickness in the shape's own section
/// and Border under Effects. They are the same ring. The shape strokes its
/// outline just inside the layer box, the border paints a ring hugging that
/// same box, and at the same width the two land on identical pixels — so with
/// both set the border simply covered the stroke and the second slider silently
/// won, in a different color.
///
/// So a layer that draws a line round itself has one control for it, its own,
/// and a layer with no line of its own — a picture, a label, a frame, a group,
/// a zoom callout, a highlight — keeps the Border row. The rule is not about
/// rectangles: on an ellipse, a line or an arrow the border draws a RECTANGLE
/// round the bounding box, which is an accident of how it is painted rather
/// than something anyone reaches for.
///
/// Shapes drawn before this change can still carry a border. Nothing is folded
/// just by opening the document, so those keep the look they were saved with;
/// the Thickness row reads whichever ring is actually visible, and the first
/// pull moves it onto the stroke, carrying its color so the box does not change
/// color under the hand.
extension Layer {

    /// True when a line round this layer is part of what it IS, rather than
    /// styling laid over it. Every shape but a highlight, which is a filled
    /// wash with no outline to set.
    public var drawsItsOwnOutline: Bool {
        guard let annotation else { return false }
        return annotation.shape != .highlight
    }

    /// The width of the one line round this shape, whichever way it is drawn.
    ///
    /// The wider of the two, because the border is painted OVER the stroke: a
    /// 4pt stroke under a 6pt border is a 6pt ring, and reading 4 there would
    /// be a row denying what is plainly on the canvas.
    var outlineWidth: CGFloat {
        guard let annotation else { return style.borderWidth }
        return max(annotation.strokeWidth, style.borderWidth)
    }

    /// The color that ring is painted, for the same reason: the border covers
    /// the stroke, so when it is the wider of the two it is the color you see.
    var outlineColorHex: String {
        guard let annotation else { return style.borderColorHex }
        return style.borderWidth >= annotation.strokeWidth && style.borderWidth > 0
            ? style.borderColorHex
            : annotation.colorHex
    }
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

    /// The picked layers the Border row can honestly reach: the ones with no
    /// line of their own. A rectangle picked alongside a screenshot takes the
    /// border off its own row and leaves the screenshot's alone.
    public var borders: LayerStyleSelection {
        LayerStyleSelection(members: members.filter { !$0.drawsItsOwnOutline },
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
            guard let layer = layer(id: id), !layer.isLocked, layer.drawsItsOwnOutline,
                  var annotation = layer.annotation else { continue }
            let color = layer.outlineColorHex
            annotation.strokeWidth = width
            annotation.colorHex = color
            updateLayer(id: id) {
                $0.content = .annotation(annotation)
                // The border goes with it. Two rings round one box, one of them
                // hidden under the other, is the thing this row exists to end.
                $0.style.borderWidth = 0
            }
            changed += 1
        }
        return changed
    }
}
