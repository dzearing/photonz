import CoreGraphics
import Foundation

/// Where the line round a layer sits relative to that layer's edge.
///
/// The same line drawn in a different place rather than three different
/// effects, which is why it is one setting under the Outline part instead of
/// three rows (`docs/design/shape-parts.md`, "How the list grows").
///
/// **Inside is what everything has always drawn.** A shape strokes a path
/// inset by half its width, so the outer edge of the stroke lands exactly on
/// the frame; a picture, a frame, a label or a group gets a ring cut out of its
/// own box. Neither has ever put a pixel past the layer edge, so every document
/// written before this opens on `inside` and paints what it always painted.
public enum BorderPosition: String, Hashable, Codable, Sendable, CaseIterable {
    /// Wholly within the layer edge: the line eats into the shape.
    case inside
    /// Straddling the edge, half in and half out.
    case center
    /// Wholly outside the edge: the shape keeps its size and the line grows it.
    case outside

    /// What the popup calls it.
    public var title: String {
        switch self {
        case .inside: "Inside"
        case .center: "Center"
        case .outside: "Outside"
        }
    }

    /// Whether a ring in this position has an edge to stand off from.
    ///
    /// Inside and outside each sit against one side of the layer's edge, so
    /// "ten points further in" and "ten points further out" both mean
    /// something. Centred straddles the edge with half the line on each side:
    /// there is no side to measure from, so no offset is offered for it and
    /// none is applied (`BorderEffect.offset`).
    public var appliesOffset: Bool { self != .center }

    /// Where the ring's OUTER edge sits relative to the layer's edge, signed:
    /// positive is past the edge, negative is inside it.
    ///
    /// This one number is the whole of the geometry. The ring is drawn as a
    /// box grown by it with a smaller one cut out, so growing it also grows
    /// the corner radius by the same amount, which is what keeps an offset
    /// ring parallel to a rounded shape instead of going square.
    ///
    /// It has to be SIGNED because an inside offset moves the ring further in,
    /// which a non-negative reach cannot say. Anything asking how much room to
    /// make reads `outset` instead, which is this clamped at nought: a ring
    /// drawn further in never asks the canvas for more space.
    public func ringOutset(width: CGFloat, offset: CGFloat = 0) -> CGFloat {
        guard width > 0 else { return 0 }
        // An offset below nought would be a second way of saying the position,
        // so it is not one: the control never offers it and the geometry
        // ignores it.
        let stand = max(0, offset)
        switch self {
        case .inside: return -stand
        case .center: return width / 2
        case .outside: return width + stand
        }
    }

    /// How far a line of `width` reaches PAST the layer edge in this position.
    ///
    /// What everything that makes ROOM reads: the bitmap a shape is drawn into
    /// grows by it on every side, and a layer's reach grows by it so a group, a
    /// frame or a drag preview makes room. Never below nought, because a ring
    /// pushed inwards takes no extra room.
    public func outset(width: CGFloat, offset: CGFloat = 0) -> CGFloat {
        max(0, ringOutset(width: width, offset: offset))
    }
}

extension AnnotationShape {

    /// Whether a line round this shape has an inside and an outside to choose
    /// between. A line and an arrow ARE their stroke, and a highlight is a slab
    /// of colour with no line at all, so for those there is no edge for one to
    /// sit on one side of.
    public var hasOutlinePosition: Bool { self == .rectangle || self == .ellipse }
}

extension AnnotationContent {

    /// How far this shape's own stroke reaches past its box, in document
    /// points. Zero unless the stroke is centred or outside.
    public var strokeOutset: CGFloat {
        guard shape.hasOutlinePosition else {
            // A line and an arrow ARE their stroke, so there is no edge for it
            // to sit on one side of, and the frame their drag left them
            // already holds half a line width of slack all round
            // (`AnnotationBuilder.layer`). What that slack does not hold is
            // the extra a SQUARE end reaches — its far corner sits width/√2
            // from the last point rather than width/2 — and an end switched
            // after the shape was drawn never grew the frame at all, so the
            // bitmap makes the difference up itself (`PathLineStyle.swift`).
            guard showsLineEnds else { return 0 }
            return max(0, strokeWidth * (lineEnd.reach - 0.5)).rounded(.up)
        }
        return strokePosition.outset(width: strokeWidth)
    }
}

extension Layer {

    /// Where this layer's one line sits: the side of the edge the ring nearest
    /// the eye is on. Every layer's edge is a Border in the Effects list now
    /// (`OutlineRetirement.swift`), so there is one answer rather than two.
    public var outlinePosition: BorderPosition { style.borderPosition }

    /// How far this layer's outline reaches past its own frame, in document
    /// points. Zero unless something is set to `center` or `outside`.
    ///
    /// Every ring counts, and the furthest of them decides: a layer can wear
    /// several Borders, and a line or an arrow still strokes its own path.
    public var outlineOutset: CGFloat {
        var reach = style.borderEffectOutset(aroundOpenLine: ringsAnOpenLine)
        if let annotation { reach = max(reach, annotation.strokeOutset) }
        if let path { reach = max(reach, path.strokeOutset) }
        return reach
    }

    /// Whether a ring round this layer has an inside to sit in.
    ///
    /// An OPEN path is a line: two sides and no interior, so Inside, Center and
    /// Outside all name the same band down the middle of it. Everything else —
    /// a closed path, a picture, a label, a frame, a group, an oval — has an
    /// inside, and its rings sit where their Position says
    /// (`BorderEffect.ringOutset(aroundOpenLine:)`).
    public var ringsAnOpenLine: Bool {
        guard let path else { return false }
        return !path.isClosed
    }

    /// The outset the layer's own CONTENT bakes into its bitmap, as opposed to
    /// the ring the renderer lays on afterwards. Only a shape has one: its
    /// stroke is drawn by the rasterizer, so the picture it hands back has to
    /// be bigger than the frame for the stroke to be in it at all.
    public var contentOutset: CGFloat { annotation?.strokeOutset ?? path?.strokeOutset ?? 0 }

    /// Everything this layer's own drawing can add past its frame: the reach of
    /// its effects plus the reach of its outline. What a drag sprite is padded
    /// by, what a dirty rect grows by, and what `renderBounds` starts from.
    public var reachPadding: CGFloat {
        (style.previewPadding(aroundOpenLine: ringsAnOpenLine) + contentOutset).rounded(.up)
    }
}
