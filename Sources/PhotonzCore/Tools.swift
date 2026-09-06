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
    case measure
    /// Paint bucket: click a layer to fill it with the foreground color
    /// (⌥ = background color). See `Fill` for per-content semantics.
    case fill
    /// Region selection (phase 17): drag a rectangular / elliptical region,
    /// or wand-click a contiguous color area. ⇧ adds, ⌥ subtracts, ⇧⌥
    /// intersects with the existing region (`SelectionRegion.Mode`).
    case rectSelect
    case ellipseSelect
    case wand
    /// Draws a frame: the fixed-size box a screen gets built on (Next,
    /// `next-frames`). A drag makes one the size you drew, a plain click drops
    /// one at the size you picked last.
    case frame

    /// The single key that picks this tool, everywhere in the product.
    ///
    /// Photoshop parity is the house rule, so V/C/T/L/R/O/G land where a
    /// Photoshop user reaches for them. Two deliberate departures, both because
    /// Photoshop has no equivalent tool to be compatible with:
    ///
    /// - **Arrow is A**, the Snagit / Preview convention for a callout arrow.
    ///   It is emphatically NOT P: P is the vector Pen everywhere else in the
    ///   product, and a key that means two things depending on which surface
    ///   you are looking at teaches people to stop trusting shortcuts.
    /// - **Measure is I**, not M. M is the Photoshop marquee, and Photoshop
    ///   itself files the Ruler under I.
    ///
    /// Nil for the marquee pair: rectangle and ellipse select share one toolbar
    /// slot, and M picks whichever you used last while ⇧M cycles them, so the
    /// key belongs to the group rather than to either tool.
    public var shortcutKey: Character? {
        switch self {
        case .select: "v"
        case .crop: "c"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .highlight: "h"
        case .text: "t"
        case .zoomCallout: "z"
        case .measure: "i"
        case .fill: "g"
        case .wand: "w"
        // F is the design-tool convention for a frame. Photoshop's F cycles
        // screen modes, which this app does not have, so nothing is displaced.
        case .frame: "f"
        case .rectSelect, .ellipseSelect: nil
        }
    }

    /// How the key is PRINTED in a tooltip or a menu row. Derived from
    /// `shortcutKey`, so what a surface teaches can never drift from what the
    /// keyboard actually does.
    public var shortcutHint: String? {
        shortcutKey.map { String($0).uppercased() }
    }

    /// The annotation shape this tool draws, nil for non-annotation tools.
    public var annotationShape: AnnotationShape? {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .highlight: .highlight
        case .select, .crop, .text, .zoomCallout, .measure, .fill,
             .rectSelect, .ellipseSelect, .wand, .frame: nil
        }
    }

    /// Whether this tool edits the selection REGION (not layer selection).
    public var isRegionSelectionTool: Bool {
        self == .rectSelect || self == .ellipseSelect || self == .wand
    }

    /// The marquee pair that shares one toolbar slot (Photoshop's M group).
    public var isMarqueeSelectTool: Bool {
        self == .rectSelect || self == .ellipseSelect
    }

    /// Whether switching TO this tool keeps the current selection region.
    /// The selection family obviously keeps it; the fill bucket keeps it
    /// because filling the region is why you made one. Drawing/crop/text
    /// tools clear it — stale ants would read as interactive there.
    public var preservesSelectionRegion: Bool {
        self == .select || self == .fill || isRegionSelectionTool
    }

    public var createsAnnotationByDrag: Bool { annotationShape != nil }

    /// The measure tool drags two reference points to create a dimension layer.
    public var createsMeasureByDrag: Bool { self == .measure }

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
        // Reserve room for the caption pill (plus its shadow) hanging off an
        // arrow's tail, so the label never clips at the frame edge — mirrors
        // MeasureBuilder's chip reservation.
        if content.hasCaption {
            var probe = content
            probe.start = start
            probe.end = end
            let size = probe.estimatedCaptionSize
            let anchor = probe.captionAnchor()
            let slack = AnnotationContent.captionShadowPadding
            box = box.union(CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                                   width: size.width, height: size.height)
                .insetBy(dx: -slack, dy: -slack))
        }
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
            // A round ending hangs past the point it marks, so this is the
            // ending's reach in every direction, not just its width.
            max(strokeWidth / 2,
                Geometry.arrowheadReach(strokeWidth: strokeWidth, scale: arrowheadScale,
                                        style: arrowheadStyle)).rounded(.up)
        case .rectangle, .ellipse, .highlight:
            0
        }
    }
}
