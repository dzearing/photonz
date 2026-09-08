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

    /// How far a line of `width` reaches PAST the layer edge in this position.
    ///
    /// This one number is the whole of what the renderer needs: the bitmap a
    /// shape is drawn into grows by it on every side, the ring round everything
    /// else is pushed out by it, and a layer's reach grows by it so a group, a
    /// frame or a drag preview makes room.
    public func outset(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        switch self {
        case .inside: return 0
        case .center: return width / 2
        case .outside: return width
        }
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
        guard shape.hasOutlinePosition else { return 0 }
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
        var reach = style.borderEffectOutset
        if let annotation { reach = max(reach, annotation.strokeOutset) }
        return reach
    }

    /// The outset the layer's own CONTENT bakes into its bitmap, as opposed to
    /// the ring the renderer lays on afterwards. Only a shape has one: its
    /// stroke is drawn by the rasterizer, so the picture it hands back has to
    /// be bigger than the frame for the stroke to be in it at all.
    public var contentOutset: CGFloat { annotation?.strokeOutset ?? 0 }

    /// Everything this layer's own drawing can add past its frame: the reach of
    /// its effects plus the reach of its outline. What a drag sprite is padded
    /// by, what a dirty rect grows by, and what `renderBounds` starts from.
    public var reachPadding: CGFloat {
        (style.previewPadding + contentOutset).rounded(.up)
    }
}
