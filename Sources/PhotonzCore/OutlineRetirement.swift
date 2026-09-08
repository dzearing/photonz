import CoreGraphics
import Foundation

/// The Outline row leaves Appearance, and a layer's edge becomes a Border in
/// the Effects list.
///
/// Reported by the user on 2026-09-07, and again on 2026-09-08 when they said
/// plainly that Outline is no longer needed now that borders are effects:
///
/// > Border is now something you add in Effects, but the old Outline row is
/// > still sitting in Appearance, so there are two ways to draw a line round a
/// > shape and no way to tell which one you are looking at. Take Outline out.
///
/// They chose, on the decision card, that a shape still ARRIVES with its edge:
/// draw a box and it looks exactly as it did, line and all, and that line is a
/// Border you can retune, reorder or take off with the cross.
///
/// ## The two edges that existed
///
/// * A **shape's own stroke** — `AnnotationContent.strokeWidth`, painted by
///   `AnnotationRasterizer` along the shape's own path. A rectangle and an
///   ellipse wore this one.
/// * A **layer ring** — a width and a colour stored on `LayerStyle`, painted as
///   a rounded rect round the layer's box. A picture, a frame, a group and a
///   highlight wore this one; on a label it outlined the LETTERS rather than
///   the box.
///
/// Both become `BorderEffect`s. The conversion is picture-for-picture, and that
/// is not a coincidence: a shape's stroke and a ring at the same width and the
/// same position land on identical pixels, which is exactly why having both was
/// a trap (`OutlineWidth.swift`), and an oval's ring has followed the oval
/// since 2026-09-08 (`RingShape.swift`).
///
/// The ONE thing that is not identical is a rounded box: a stroke rode a path
/// half its own width inside the frame, so a box with an 8pt corner and a 3pt
/// line had a 9.5pt curve at its outer edge, while the ring that replaces it
/// hugs the box and curves by the 8 the panel says. The number somebody typed
/// is kept rather than rewritten to 9.5, because a Corner Radius that changes
/// itself on open is a worse surprise than half a line width of curve, and
/// Corner Radius now means the curve you can see.
///
/// ## Where the converted ring lands in the list
///
/// At the FOOT of it. The list paints from the bottom up, top of the list
/// nearest the eye, and the canvas used to paint the shape's stroke first, the
/// layer's ring over that, and every added border over both. So a box wearing
/// all three opens with the added borders where they were, then the ring, then
/// the stroke — same order, same picture.
///
/// ## What is NOT converted
///
/// A line and an arrow ARE their stroke: taking it off would leave nothing on
/// the canvas, so they keep it and it stays in the shape's own settings beside
/// the ending and the head size. A highlight's stroke colour is the WASH it
/// paints, not a line round anything, so it stays too.
extension Layer {

    /// This layer with its edge moved into the Effects list, and every layer
    /// inside it likewise.
    ///
    /// Safe to run twice: a shape whose stroke has already moved has no stroke
    /// left to move, so nothing happens the second time.
    public func retiringItsOutline() -> Layer {
        var layer = self
        if case .group(var group) = layer.content {
            group.children = group.children.map { $0.retiringItsOutline() }
            layer.content = .group(group)
        }
        layer.moveItsOutlineIntoEffects()
        return layer
    }

    /// The same move on this layer alone, without walking what is inside it.
    ///
    /// Called from `Layer.init`, so a shape built in code — a starter
    /// component, the shape tool, a test — comes out the same shape a document
    /// opens as. A group's children were normalised when THEY were built, so
    /// there is nothing to walk from there.
    mutating func moveItsOutlineIntoEffects() {
        guard var annotation, annotation.drawsARingRatherThanBeingOne,
              annotation.strokeWidth > 0 else { return }
        var border = BorderEffect(width: annotation.strokeWidth,
                                  position: annotation.strokePosition)
        // The whole paint, not the flat colour it stands for: a box drawn with
        // a gradient armed has a gradient outline, and flattening it on open
        // would change a picture somebody saved.
        border.paint = annotation.paint
        // Under everything already in the list, which is where it painted.
        style.effects.append(.border(border))
        annotation.strokeWidth = 0
        content = .annotation(annotation)
    }
}

extension AnnotationContent {

    /// Whether this shape's stroke is a line round something, rather than the
    /// thing itself.
    ///
    /// A box and an oval have an inside, so the line round them can come off
    /// and be set again; that line is what became a Border. A line and an arrow
    /// have no inside at all, and a highlight's "stroke" is the wash it paints,
    /// so none of the three has an edge to retire.
    var drawsARingRatherThanBeingOne: Bool {
        switch shape {
        case .rectangle, .ellipse: return true
        case .line, .arrow, .highlight: return false
        }
    }
}
