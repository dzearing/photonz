import CoreGraphics
import Foundation

/// The outline a ring round a layer follows.
///
/// Every ring — the layer's own Outline, and each Border under Effects — used
/// to be drawn as a rounded rectangle round the layer's box, because a box is
/// all most layers have. On an ellipse that came out as a SQUARE frame round a
/// red oval (reported on the probe, 2026-09-08), which is an accident of how
/// the ring was painted rather than anything anyone reaches for.
///
/// So the ring asks the layer what its silhouette is. A shape that draws a path
/// of its own answers with that path; everything else — a picture, a label, a
/// frame, a group — has no path, and its box is the honest answer.
public enum RingShape: String, Hashable, Codable, Sendable {
    /// The layer's box, curved by whatever corner radius it carries.
    case box
    /// The oval inscribed in the layer's box.
    case ellipse
}

extension Layer {

    /// What a ring round this layer hugs.
    ///
    /// Only an ellipse has a silhouette that is not its box. A line and an
    /// arrow ARE their stroke, so a ring round one is a different idea and is
    /// not answered here; a highlight is a slab of colour with a box for an
    /// edge; and a rectangle's silhouette is its box, curved by its corner
    /// radius (`boxCornerRadius`).
    public var ringShape: RingShape {
        annotation?.shape == .ellipse ? .ellipse : .box
    }
}
