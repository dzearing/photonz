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

    /// The same, as one number.
    public func selectionOutlineRadius(box: CGRect) -> CGFloat {
        let radii = selectionOutlineRadii(box: box)
        return radii.uniform ?? radii.largest
    }
}
