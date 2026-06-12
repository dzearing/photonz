import CoreGraphics
import Foundation

/// The editor's modal tool. `select` is the resting state (hit-test, move,
/// marquee); annotation tools create layers by dragging; `crop` and `text`
/// have their own interactions (phases 4 and 3.4).
public enum Tool: String, CaseIterable, Hashable, Codable, Sendable {
    case select
    case crop
    case arrow
    case line
    case rectangle
    case ellipse
    case highlight
    case text
    case zoomCallout

    /// The annotation shape this tool draws, nil for non-annotation tools.
    public var annotationShape: AnnotationShape? {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .highlight: .highlight
        case .select, .crop, .text, .zoomCallout: nil
        }
    }

    public var createsAnnotationByDrag: Bool { annotationShape != nil }

    /// Smart-default content for this tool: red strokes, yellow highlight
    /// (system palette colors). Nil for non-annotation tools.
    public var defaultAnnotation: AnnotationContent? {
        AnnotationStyles().content(for: self)
    }
}

/// An in-progress drag-to-create annotation, tracked in document coordinates.
/// Mirrors `MarqueeDrag`: the canvas feeds it pointer positions, all geometry
/// decisions live here.
public struct AnnotationDrag: Equatable, Sendable {
    public var anchor: CGPoint
    public var current: CGPoint

    public init(anchor: CGPoint) {
        self.anchor = anchor
        self.current = anchor
    }

    public mutating func update(to point: CGPoint) {
        current = point
    }

    /// The effective endpoint. Constrained (⇧): lines/arrows snap to the
    /// nearest 45° preserving length; box shapes square off the longer axis.
    public func end(constrained: Bool, shape: AnnotationShape) -> CGPoint {
        guard constrained else { return current }
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        switch shape {
        case .line, .arrow:
            let length = hypot(dx, dy)
            guard length > 0 else { return current }
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: anchor.x + cos(angle) * length,
                           y: anchor.y + sin(angle) * length)
        case .rectangle, .ellipse, .highlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: anchor.x + (dx < 0 ? -side : side),
                           y: anchor.y + (dy < 0 ? -side : side))
        }
    }

    /// Whether the pointer moved so little this is a click, not a drag.
    /// Tolerance is in view points so it feels the same at any zoom.
    public func isClick(atZoom zoom: CGFloat, tolerance: CGFloat = 4) -> Bool {
        hypot(current.x - anchor.x, current.y - anchor.y) * zoom < tolerance
    }
}

/// Builds annotation layers from completed drags.
public enum AnnotationBuilder {

    /// The layer a drag from `start` to `end` (document coordinates) creates.
    /// The frame is the drag's bounding box padded by the content's render
    /// overhang (round caps, arrowhead wings) so rasterization never clips,
    /// and the content's start/end are re-expressed in layer-local coords.
    public static func layer(content: AnnotationContent, from start: CGPoint, to end: CGPoint) -> Layer {
        var content = content
        let pad = content.renderPadding
        var box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
            .insetBy(dx: -pad, dy: -pad)
        // The rasterizer needs at least one pixel each way (a perfectly
        // horizontal highlight drag would otherwise collapse).
        box.size.width = max(box.size.width, 1)
        box.size.height = max(box.size.height, 1)
        content.start = CGPoint(x: start.x - box.minX, y: start.y - box.minY)
        content.end = CGPoint(x: end.x - box.minX, y: end.y - box.minY)
        return Layer(name: name(for: content.shape), content: .annotation(content), frame: box)
    }

    private static func name(for shape: AnnotationShape) -> String {
        switch shape {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        }
    }
}

extension AnnotationContent {
    /// How far drawing can extend beyond the start/end bounding box.
    /// Rectangles/ellipses inset their stroke and highlights fill, so only
    /// open strokes (caps) and arrowheads (wings) overhang.
    public var renderPadding: CGFloat {
        switch shape {
        case .line:
            (strokeWidth / 2).rounded(.up)
        case .arrow:
            max(strokeWidth / 2, Geometry.arrowheadHalfWidth(strokeWidth: strokeWidth)).rounded(.up)
        case .rectangle, .ellipse, .highlight:
            0
        }
    }
}
