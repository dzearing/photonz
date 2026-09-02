import CoreGraphics
import Foundation

/// The snap lines the measurements ALREADY on the canvas offer to the one being
/// dragged, so a page full of callouts can be lined up with each other instead
/// of by eye.
///
/// This is deliberately measurement-to-measurement only. Snapping to the
/// picture's own content is what `EdgeMap` + `EdgeSnapping` already do for the
/// feet; a redliner lining up a column of readouts is asking for something
/// else: "put this chip where those chips are".
///
/// Two candidate sets, because the two handles want different things:
/// * `chipLines` — where the other readouts CENTRE. What a dragged chip lines
///   up with. It follows a readout that has been pushed clear of its subject,
///   because that is the chip a person can see.
/// * `lines` — the feet line, the head line and the two ends of every other
///   caliper. What a dragged foot lines up with, so two calipers can share a
///   start line.
public enum MeasureSnapping {

    /// Positions closer together than this are the same line.
    private static let duplicateTolerance: CGFloat = 0.01

    /// The measurement as it sits in DOCUMENT space. A layer stores its feet
    /// layer-local, and every line here is compared against a document-space
    /// pointer. Nil for a layer that is not a measurement.
    public static func documentMeasure(_ layer: Layer) -> MeasureContent? {
        guard var m = layer.measure,
              let start = layer.measureEndpoint(.start),
              let end = layer.measureEndpoint(.end) else { return nil }
        m.start = start
        m.end = end
        return m
    }

    /// Where a measurement's readout chip centres, in document space, or nil
    /// when it has no readout. The chip's own placement is applied, so a
    /// readout that moved out of the way of its subject reports where it
    /// actually sits rather than the head line it came from.
    public static func chipCentre(of layer: Layer) -> CGPoint? {
        guard let m = documentMeasure(layer), m.showLabel else { return nil }
        return m.labelPosition(chipSize: m.estimatedLabelSize)
    }

    /// The readout-chip centre lines every other visible measurement offers.
    /// Both axes come back: a chip only moves on one of them, and which one
    /// depends on the caliper doing the dragging. Pass nil to exclude nothing
    /// (a measurement being placed is not on the canvas yet).
    public static func chipLines(in document: PhotonzDocument,
                                 excluding id: UUID?) -> EdgeSnapping.GuideLines {
        var vertical: [CGFloat] = [], horizontal: [CGFloat] = []
        for layer in others(in: document, excluding: id) {
            guard let centre = chipCentre(of: layer) else { continue }
            vertical.append(centre.x)
            horizontal.append(centre.y)
        }
        return EdgeSnapping.GuideLines(vertical: tidied(vertical), horizontal: tidied(horizontal))
    }

    /// Every structural line the other visible measurements draw: each
    /// caliper's feet line, its head line, and the two ends of both. Pass nil
    /// to exclude nothing (a measurement being placed is not on the canvas yet).
    public static func lines(in document: PhotonzDocument,
                             excluding id: UUID?) -> EdgeSnapping.GuideLines {
        var vertical: [CGFloat] = [], horizontal: [CGFloat] = []
        for layer in others(in: document, excluding: id) {
            guard let m = documentMeasure(layer) else { continue }
            let g = m.caliperGeometry()
            for point in [g.footA, g.footB, g.headA, g.headB] {
                vertical.append(point.x)
                horizontal.append(point.y)
            }
        }
        return EdgeSnapping.GuideLines(vertical: tidied(vertical), horizontal: tidied(horizontal))
    }

    /// The measurement layers a drag may line up with: visible, and not the one
    /// in hand.
    private static func others(in document: PhotonzDocument, excluding id: UUID?) -> [Layer] {
        document.layers.filter { $0.id != id && $0.isVisible && $0.measure != nil }
    }

    /// Sorted, with lines that land on top of each other collapsed — two
    /// calipers sharing an edge should offer that edge once.
    private static func tidied(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values.sorted() where value.isFinite {
            if let last = result.last, abs(value - last) <= duplicateTolerance { continue }
            result.append(value)
        }
        return result
    }
}
