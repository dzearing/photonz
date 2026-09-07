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

    /// The edges of the LAYERS on the canvas: every visible layer's left, right,
    /// top and bottom, in document space.
    ///
    /// This is the answer to a caliper measuring a box the app drew itself. The
    /// picture's own edges (`EdgeMap`) are approximated from gradients, and a
    /// shape drawn ON TOP of the picture is not in that map at all, so before
    /// this there was nothing to catch a foot on a rectangle you had just
    /// drawn: a 128 tall box read 124, because the outline a hand aims at is
    /// drawn inside the box and the hand landed on the middle of it. A layer's
    /// box is exact, so `EdgeSnapping` treats these as known rather than
    /// guessed and lets them win outright.
    ///
    /// The box is the one a person can SEE, and for a stroked shape that IS the
    /// layer box: the renderer insets the path by half the stroke before
    /// stroking, so the outline's outer edge lands exactly on the box. Measuring
    /// a bordered button therefore gives its visible outer size, which is what a
    /// redline means by the size of a button.
    ///
    /// Measurements are left out: a caliper's bounding box is not something
    /// anyone aims at, and `lines(in:excluding:)` already offers their feet and
    /// head lines precisely. Pass the id of the caliper in hand to keep its own
    /// box out; pass nil for one that is not a layer yet.
    public static func layerLines(in document: PhotonzDocument,
                                  excluding id: UUID?) -> EdgeSnapping.GuideLines {
        var vertical: [CGFloat] = [], horizontal: [CGFloat] = []
        // Kept out through `snapPeers`' own exclusion list rather than filtered
        // afterwards: it hands back boxes, not layers, and it is the one place
        // that knows which of them a drag may line up with at all.
        var ids = Set(document.layers.flatMap(\.selfAndDescendants)
            .filter { $0.measure != nil }.map(\.id))
        if let id { ids.insert(id) }
        for box in document.snapPeers(excluding: ids) where !box.isNull {
            vertical.append(box.minX)
            vertical.append(box.maxX)
            horizontal.append(box.minY)
            horizontal.append(box.maxY)
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
