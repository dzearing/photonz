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

    /// Whether the Outline row can offer this layer a Position at all: a shape
    /// with an edge, or anything that takes a ring round its box. Text is out,
    /// because its outline follows the letters rather than the box, so inside
    /// and outside would mean nothing on it.
    public var hasOutlinePosition: Bool {
        if let annotation { return annotation.shape.hasOutlinePosition }
        if case .text = content { return false }
        return true
    }

    /// Where this layer's one line sits, whichever ring it draws.
    ///
    /// One reading for both kinds, the way `outlineWidth` is one reading: a
    /// shape strokes its own path and a picture takes a ring round its box, and
    /// nothing a person does differs (`OutlineWidth.swift`).
    public var outlinePosition: BorderPosition {
        guard let annotation, annotation.shape.hasOutlinePosition else { return style.borderPosition }
        // The border is painted OVER the stroke, so when it is the wider of the
        // two it is the ring you can see, and its position is the one the row
        // has to report.
        return style.borderWidth > annotation.strokeWidth
            ? style.borderPosition
            : annotation.strokePosition
    }

    /// How far this layer's outline reaches past its own frame, in document
    /// points. Zero unless something is set to `center` or `outside`.
    ///
    /// Both rings count, because a layer can carry both: a legacy shape with a
    /// stroke of its own AND a border ring left by the old Effects slider.
    public var outlineOutset: CGFloat {
        var reach = style.borderPosition.outset(width: style.borderWidth)
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

extension PhotonzDocument {

    /// What the Outline row's Position reads over a set of picked layers,
    /// whichever ring each one draws: the answer they all wear, or that they
    /// differ.
    public func outlinePositionReading(layerIDs: [UUID]) -> StyleReading<BorderPosition> {
        let positions = layerIDs.compactMap { layer(id: $0) }
            .filter { !$0.isLocked && $0.hasOutlinePosition }
            .map(\.outlinePosition)
        guard let first = positions.first else { return StyleReading(value: nil, isMixed: false) }
        return StyleReading(value: first,
                            isMixed: positions.dropFirst().contains { $0 != first })
    }

    /// One pick on the Outline row's Position, every picked layer, whichever
    /// ring each one draws. Returns how many changed, so a caller can tell a
    /// no-op from an edit.
    ///
    /// A shape gets it on its own stroke and everything else on its border
    /// ring, exactly the way `setRingWidth` splits, so one control means one
    /// thing however mixed the selection is.
    @discardableResult
    public mutating func setOutlinePosition(layerIDs: [UUID], to position: BorderPosition) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, layer.hasOutlinePosition,
                  layer.outlinePosition != position else { continue }
            updateLayer(id: id) { target in
                if var annotation = target.annotation, annotation.shape.hasOutlinePosition {
                    annotation.strokePosition = position
                    target.content = .annotation(annotation)
                }
                // The border ring moves too, so a layer carrying both never
                // ends up with one line inside and one outside.
                target.style.borderPosition = position
            }
            changed += 1
        }
        return changed
    }
}
