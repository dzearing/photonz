import CoreGraphics
import Foundation

/// The path the outline round a picked layer follows.
///
/// The outline hugs what the layer DRAWS rather than the box it is stored in —
/// that is why a small captioned arrow is ringed round its stroke and not round
/// the padded frame it rasterizes into. A rounded rectangle broke that promise:
/// the outline was always four straight lines, so pulling Corner Radius right
/// up left it cutting across every corner with the shape curving away inside it
/// (seen on the probe, 2026-09-08).
///
/// So it curves by the same radius everything else round the box curves by
/// (`Layer.boxCornerRadius(boxSize:)`), which is what the shape's silhouette,
/// its mask and every ring already follow. The eight handles do NOT move onto
/// the curve: they mark the corners of the box a drag grabs, which is still
/// square.
public enum SelectionOutlineShape {

    /// The mocks' softening of a ring that hugs the box, in screen points:
    /// a hairline that reads as square at every size and never clamps.
    public static let boxSoftening: CGFloat = 2

    /// `box` in document points, `cornerRadii` the curve at each of its four
    /// corners, and `transform` everything between there and the screen — the
    /// layer's own rotate/skew and the camera, in one go, so a turned shape's
    /// outline curves with it.
    ///
    /// One path builder for all of it (`CornerRadii.path`), which clamps
    /// rounding past fully round exactly as the rasterizer does, so the outline
    /// never bulges outside the box.
    public static func path(box: CGRect, cornerRadii: CornerRadii,
                            transform: CGAffineTransform = .identity) -> CGPath {
        cornerRadii.path(in: box, transform: transform)
    }

    /// The same, from one number: every corner the same.
    public static func path(box: CGRect, cornerRadius: CGFloat,
                            transform: CGAffineTransform = .identity) -> CGPath {
        path(box: box, cornerRadii: CornerRadii(cornerRadius), transform: transform)
    }
}

extension Layer {

    /// How round the outline round `box` is, where `box` is the ink the layer
    /// puts down, in document points.
    ///
    /// Only a layer with corners has one to curve: an ellipse, a line and an
    /// arrow answer nought, so they are marked exactly as they always were.
    public func selectionOutlineRadii(box: CGRect) -> CornerRadii {
        guard hasCorners else { return .none }
        return boxCornerRadii(boxSize: box.size)
    }

    /// How round the ring round a picked layer is, in document points, when
    /// the canvas shows the document at `zoom` view points per point.
    ///
    /// `huggingBox` is the mocks' frame (selection.css `.sel-ring`: "hug the
    /// bounds", "never trace the object's shape"): every layer, rounded or not,
    /// is ringed by its box softened by `SelectionOutlineShape.boxSoftening`
    /// screen points, which reads as square at every size, so the ring never
    /// passes for a rounded shape's own border. Otherwise the ring curves with
    /// the shape (`selectionOutlineRadii(box:)`).
    public func pickedRingRadii(box: CGRect, huggingBox: Bool, zoom: CGFloat) -> CornerRadii {
        guard huggingBox else { return selectionOutlineRadii(box: box) }
        let scale = zoom.isFinite && zoom > 0 ? zoom : 1
        return CornerRadii(SelectionOutlineShape.boxSoftening / scale)
    }

    /// The same, as one number.
    public func selectionOutlineRadius(box: CGRect) -> CGFloat {
        let radii = selectionOutlineRadii(box: box)
        return radii.uniform ?? radii.largest
    }
}
