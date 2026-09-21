import CoreGraphics
import Foundation

/// Growing a layer: a real magnification, not a bigger box round the same
/// drawing.
///
/// Dragging a handle and telling a layer to scale are two different things,
/// and the app was doing the first when it was asked for the second. A handle
/// RE-FITS: a card dragged wider keeps its label the size it was, because type
/// and line weight are measured in points and points do not change when a box
/// does. Scale MAGNIFIES: everything on the layer is multiplied together — the
/// shape, the line round it, the words, the corner it is rounded with, the
/// shadow under it — which is exactly what `scale()` in an SVG file does, and
/// so is the only reading under which the canvas, the looping preview and an
/// exported animated SVG can agree about how big something is at a given
/// moment.
///
/// Nothing here is ever stored. This is asked for at the moment a frame is
/// drawn and thrown away after, the same bargain every other motion strikes.
extension Layer {

    /// This layer drawn `factor` times as big, magnified about `pivot` in the
    /// space this layer's own frame is stated in.
    ///
    /// The geometry of each content kind is re-fitted through `resized(to:)`,
    /// which is the one place that knows how to scale an arrow's endpoints, a
    /// path's anchors and a caliper's feet, so there is no second remap here to
    /// drift from it. What `resized(to:)` deliberately leaves alone — the
    /// lengths measured in points — is multiplied on top, because that is the
    /// whole difference between a re-fit and a magnification.
    ///
    /// A group magnifies whole rather than placing its pieces: every child
    /// moves outward from the pivot and grows by the same amount, so the
    /// drawing keeps its shape. Placement rules answer "the container changed
    /// size, where do I go"; they have no say in a magnification, where the
    /// answer is always "everywhere, by the same amount".
    public func drawnLarger(by factor: CGFloat, about pivot: CGPoint) -> Layer {
        // Gone, not full size: a layer told to be nought percent has no box at
        // all, and a renderer handed a box with nothing in it draws nothing.
        guard factor.isFinite, factor > 0 else {
            var gone = self
            gone.frame = CGRect(origin: pivot, size: .zero)
            return gone
        }
        guard factor != 1 else { return self }

        let box = frame.standardized
        let grown = CGRect(x: pivot.x + (box.minX - pivot.x) * factor,
                           y: pivot.y + (box.minY - pivot.y) * factor,
                           width: box.width * factor,
                           height: box.height * factor)

        var out = self
        out.style = style.magnified(by: factor)
        out.crop = crop?.magnified(by: factor)
        // The lengths stated in points, multiplied BEFORE the geometry is
        // re-fitted: a label's box is as tall as its words need, so the words
        // have to be their new size before anybody measures the box, and an
        // arrow's frame reserves room for its cap, so the cap has to be its new
        // thickness before that room is worked out.
        out.content = content.inkDrawnLarger(by: factor)

        if case .group(var group) = out.content {
            // A child's numbers are its group's own, so the children magnify
            // about that corner and the group's corner magnifies about the
            // pivot. Composed, every point in the group ends up `factor` times
            // as far from the pivot as it was, which is the definition.
            group.children = group.children.map { $0.drawnLarger(by: factor, about: .zero) }
            group.layout = group.layout?.magnified(by: factor)
            out.content = .group(group)
            out.frame = grown
            return out
        }
        // A shape with nothing drawn in it — both ends of a box at the same
        // point — has no drawing to magnify, and re-fitting one collapses its
        // box to the single point the rasterizer insists on having. So its box
        // grows and its content is left exactly as it is, which beats handing
        // back a layer one point across.
        guard !drawsNothingOfItsOwn else {
            out.frame = grown
            return out
        }
        return out.resized(to: grown)
    }

    /// Whether this layer's content covers no area at all, so there is nothing
    /// in it for a magnification to make bigger.
    private var drawsNothingOfItsOwn: Bool {
        switch content {
        case let .annotation(annotation):
            return annotation.start == annotation.end
        case let .measure(measure):
            return measure.start == measure.end
        default:
            return false
        }
    }
}

extension LayerContent {

    /// This content with every length it states in POINTS multiplied: the line
    /// it is drawn with, the corner it is rounded with, the size of its type.
    ///
    /// The other half of a magnification. The geometry — where the anchors
    /// are, where the endpoints are — is `Layer.resized(to:)`'s business and is
    /// untouched here, so the two never disagree about the same number.
    func inkDrawnLarger(by factor: CGFloat) -> LayerContent {
        guard factor.isFinite, factor > 0, factor != 1 else { return self }
        switch self {
        // Sound draws no ink, so there is none to draw larger.
        case .sound:
            return self
        case .path(var path):
            path.strokeWidth *= factor
            return .path(path)
        case .annotation(var annotation):
            annotation.strokeWidth *= factor
            annotation.cornerRadii = annotation.cornerRadii.scaled(by: factor)
            annotation.captionFontSize *= factor
            return .annotation(annotation)
        case .text(var text):
            text.fontSize *= factor
            return .text(text)
        case .measure(var measure):
            measure.strokeWidth *= factor
            measure.headOffset *= factor
            measure.chipBorderWidth *= factor
            measure.labelScale *= factor
            return .measure(measure)
        case .lens(let lens):
            // A lens says its blur strength and its block size in points like
            // everything else here, and it already knows how to restate them.
            return .lens(lens.magnified(by: factor))
        // A photograph and a collage are drawn INTO their box, so they grow
        // with it for free. A zoom callout aims at a region of the canvas that
        // the magnification of one layer does not move, and its own re-fit
        // works its magnification out again from the new box. A group's pieces
        // are magnified one by one above.
        case .image, .collage, .zoomCallout, .group:
            return self
        }
    }
}
